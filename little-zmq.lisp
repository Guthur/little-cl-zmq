(in-package #:little-zmq)

(declaim (optimize (speed 3)))

(defmacro with-context ((ctx &optional (io-threads 1)) &body body)
  `(let ((,ctx (%zmq:init ,io-threads)))
     (unwind-protect
	  (progn
	    ,@body)
       (%zmq:term ,ctx))))

(defmacro with-socket ((socket context type &rest parameters)
		       &body body)
  `(let ((,socket (%zmq:make-socket ,context ,type ,@parameters)))
     (unwind-protect
	  (progn
	    ,@body)
       (%zmq:close-socket ,socket))))

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

(defmethod sendmsg ((socket %zmq::socket) (data (eql nil))
		    &key (send-more nil) (eintr-retry t))
  (with-message (msg)
    (sendmsg socket msg :eintr-retry eintr-retry :send-more send-more)))

(defmethod sendmsg ((socket %zmq::socket) (data vector)
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
	   (type (vector (unsigned-byte 8) *) data))
  (with-message (msg data)
    (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod sendmsg ((socket %zmq::socket) (data string)
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry))
  (with-message (msg data)
    (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod sendmsg ((socket %zmq::socket) (data message)
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry))
  (with-zmq-eintr-retry eintr-retry
    (%zmq:sendmsg (slot-value socket '%zmq::ptr)
		  (msg-t-ptr data)
		  (if send-more %zmq::+sndmore+ 0))))

(defmethod sendmsg ((socket %zmq::socket) (data function)
		    &key (send-more nil) (eintr-retry t))
  (with-message (msg)
    (multiple-value-bind (msg more)
	(funcall data msg)
      (if more
	  (progn
	    (sendmsg socket msg :send-more t :eintr-retry eintr-retry)
	    (sendmsg socket data :send-more send-more :eintr-retry eintr-retry))
	  (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))))

(defun recvmsg (socket message &key (blocking t) (as 'message) (eintr-retry t))
  (declare (type (boolean) eintr-retry blocking)
	   (type message message)
	   (type symbol as)
	   (type %zmq::socket socket))
  (let ((blocking (if blocking 0 %zmq::+dontwait+)))
    (with-zmq-eintr-retry eintr-retry
      (%zmq:recvmsg (slot-value socket '%zmq::ptr)
		    (msg-t-ptr message)
		    blocking))
    (unless (eql as 'message)
      (change-class message as))
    message))

(defun recvall (socket &key (blocking t) (eintr-retry))
  (let ((more t))
    (lambda (msg &optional (message-type 'message))
      (if more
	  (progn
	    (recvmsg socket msg :as message-type
				:blocking blocking
				:eintr-retry eintr-retry)
	    (setf more (%zmq:rcvmore socket))
	    (values msg more))
	  (values nil nil)))))

#++(defun recvall (socket msg-list &key (blocking t)
			 (eintr-retry t))
  (let ((msgs (loop
		:collect (if (parts msg-list)
			     (progn			       
			       (recvmsg socket (pop (parts msg-list))
					:blocking blocking
					:eintr-retry eintr-retry))
			     (progn
			       (recvmsg socket (make-message nil))))
		:while (%zmq:rcvmore socket))))
    (destroy-msg-list msg-list)
    (setf (parts msg-list) msgs)))
