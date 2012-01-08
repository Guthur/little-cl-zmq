(in-package #:little-zmq)

#++(declaim (optimize (speed 3)))


(defun call-with-retry (predicate thunk)
  (declare (inline call-with-retry))
  (declare (type (function (condition) boolean) predicate)
	   (type (function nil) thunk))
  (tagbody retry
     (return-from call-with-retry
       (handler-bind ((t (lambda (condition)			   
                           (when (funcall predicate condition)
                             (go retry)))))
         (funcall thunk)))))

(defmacro with-zmq-eintr-retry (&body body)
  `(call-with-retry
    (lambda (condition)
      (and (typep condition '%zmq::zmq-error)
           (eql (%zmq::error-number condition)
                %zmq::+eintr+)))
    (lambda ()
      ,@body)))

(defmacro with-context ((ctx &optional (io-threads 1)) &body body)
  `(let ((,ctx (%zmq:init ,io-threads)))
     (unwind-protect
	  ,@body
       (%zmq:term ,ctx))))

(defmacro with-socket (((skt ctx type) &key connect bind)
		       &body body)
  `(let* ((,skt (%zmq:make-socket ,ctx
				  (%zmq:kwsym-value ,type))))
     (unwind-protect
	  ,(cond
	     (bind
	      `(bind ,skt ,bind))
	     (connect
	      `(connect ,skt ,connect)))
       ,@body
       (%zmq:close-socket ,skt))))

(defmacro with-sockets (socket-list &body body)
  (if socket-list
      `(with-socket ,(car socket-list)
	 (with-sockets ,(cdr socket-list)
	   ,@body))
      `(progn ,@body)))

(defun bind (socket address)
  (%zmq::bind (slot-value socket '%zmq::ptr) address))

(defun connect (socket address)
  (%zmq::connect (slot-value socket '%zmq::ptr) address))

(defmethod sendmsg ((socket %zmq::socket) (data vector)
		    &key (send-more nil) (eintr-retry t))
  (let ((msg (make-octet-message data)))
    (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod sendmsg ((socket %zmq::socket) (data string)
		    &key (send-more nil) (eintr-retry t))
  (let ((msg (make-string-message data)))
    (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod sendmsg ((socket %zmq::socket) (data message)
		    &key (send-more nil) (eintr-retry t))
  (if eintr-retry
      (with-zmq-eintr-retry
	(%zmq:sendmsg (slot-value socket '%zmq::ptr)
		      (msg-t-ptr data)
		      (if send-more (%zmq:kwsym-value :sndmore) 0)))
      (%zmq:sendmsg (slot-value socket '%zmq::ptr)
		      (msg-t-ptr data)
		      (if send-more (%zmq:kwsym-value :sndmore) 0))))

(defmethod recvmsg ((socket %zmq::socket)
		    &key (blocking t) (message-type 'message) (reuse-msg nil)
		      (eintr-retry t))
  (let ((msg (if reuse-msg
		 reuse-msg
		 (make-instance 'message))))
    (if eintr-retry
	(with-zmq-eintr-retry
	  (%zmq:recvmsg (slot-value socket '%zmq::ptr)
			(slot-value msg 'msg-t)
			(if blocking 0 (%zmq:kwsym-value :dontwait))))
	(%zmq:recvmsg (slot-value socket '%zmq::ptr)
		      (slot-value msg 'msg-t)
		      (if blocking 0 (%zmq:kwsym-value :dontwait))))
    (unless (eql message-type 'message) 
      (change-class msg message-type))
    msg))
