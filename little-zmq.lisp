(in-package #:little-zmq)

#++(declaim (optimize (speed 3)))

(defmacro with-context ((ctx &optional (io-threads 1)) &body body)
  `(let ((,ctx (%zmq:init ,io-threads)))
     (unwind-protect
	  (progn
	    ,@body)
       (%zmq:term ,ctx))))

(defmacro with-socket (((skt ctx type) &key connect bind identity)
		       &body body)
  `(let* ((,skt (%zmq:make-socket ,ctx
				  (%zmq:kwsym-value ,type))))
     (unwind-protect
	  (progn
	    ,(when identity
	       `(setf (%zmq:identity ,skt) ,identity))
	    ,(cond
	       (bind
		`(bind ,skt ,bind))
	       (connect
		`(dolist (addr (alexandria:ensure-list ,connect))
		   (connect ,skt addr))))
	    ,@body)
       (%zmq:close-socket ,skt))))

(defmacro with-sockets (socket-list &body body)
  (if socket-list
      `(with-socket ,(car socket-list)
	 (with-sockets ,(cdr socket-list)
	   ,@body))
      `(progn ,@body)))

(defun bind (socket address)
  (declare (type string address)
	   (type %zmq::socket socket))
  (%zmq::bind (slot-value socket '%zmq::ptr) address))

(defun connect (socket address)
  (declare (type string address)
	   (type %zmq::socket socket))
  (%zmq::connect (slot-value socket '%zmq::ptr) address))

(defmethod sendmsg ((socket %zmq::socket) (data cons)
		    &key  (eintr-retry t))
  (declare (type (cons (or message
			   string
			   (vector (unsigned-byte 8)))
		       (or cons
			   null)) data)
	   (type (boolean) eintr-retry))
  (labels ((send (msg-list)
	     (cond
	       ((null (cdr msg-list))
		(sendmsg socket (car msg-list) :eintr-retry eintr-retry))
	       (t
		(sendmsg socket (car msg-list) :eintr-retry eintr-retry
					       :send-more t)
		(send (cdr msg-list))))))
    (send data)))

(defmethod sendmsg ((socket %zmq::socket) (data vector)
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
	   (type (vector (unsigned-byte 8))))
  (let ((msg (make-octet-message data)))
    (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod sendmsg ((socket %zmq::socket) (data string)
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry))
  (let ((msg (make-string-message data)))
    (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod sendmsg ((socket %zmq::socket) (data message)
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry))
  (with-zmq-eintr-retry eintr-retry
    (%zmq:sendmsg (slot-value socket '%zmq::ptr)
		  (msg-t-ptr data)
		  (if send-more (%zmq:kwsym-value :sndmore) 0))))

(defun recvmsg (socket &key (blocking t) (message-type 'message) (reuse-msg nil)
			 (eintr-retry t))
  (declare (type (boolean) eintr-retry blocking)
	   (type (or message null) reuse-msg)
	   (type symbol message-type)
	   (type %zmq::socket socket))
  (let ((msg (if reuse-msg
		 reuse-msg
		 (make-instance 'message))))
    (with-zmq-eintr-retry eintr-retry
      (%zmq:recvmsg (slot-value socket '%zmq::ptr)
		    (slot-value msg 'msg-t)
		    (if blocking 0 (%zmq:kwsym-value :dontwait))))    
    (unless (eql message-type 'message) 
      (change-class msg message-type))
    msg))

(defun recvall (socket &key (blocking t)
			 (eintr-retry t))
  (loop
    :collect (recvmsg socket :blocking blocking :eintr-retry eintr-retry)
    :while (%zmq:rcvmore socket)))
