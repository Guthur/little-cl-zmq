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

(defgeneric sendmsg (socket data &key eintr-retry send-more))

(defmethod sendmsg ((socket %zmq::socket) (data cons)
		    &key (eintr-retry t) send-more)
  (declare (type (cons (or message
			   string
			   (vector (unsigned-byte 8)))
		       (or cons
			   null)) data)
	   (type (boolean) eintr-retry)
	   (type %zmq::socket socket))
  (labels ((send (msg-list)
	     (cond
	       ((null (cdr msg-list))
		(sendmsg socket (car msg-list) :eintr-retry eintr-retry
					       :send-more send-more))
	       (t
		(sendmsg socket (car msg-list) :eintr-retry eintr-retry
					       :send-more t)
		(send (cdr msg-list))))))
    (send data)))

(defmethod sendmsg ((socket %zmq::socket) (data (eql nil))
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
	   (type %zmq::socket socket)
	   (inline sendmsg))
  (with-message (msg)
    (sendmsg socket msg :eintr-retry eintr-retry :send-more send-more)))

(defmethod sendmsg ((socket %zmq::socket) (data vector)
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
	   (type %zmq::socket socket)
	   (type (vector (unsigned-byte 8) *) data)
	   (inline sendmsg))
  (with-message (msg data)
    (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod sendmsg ((socket %zmq::socket) (data string)
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
	   (type %zmq::socket socket)
	   (type string data)
	   (inline sendmsg))
  (with-message (msg data)
    (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))

(defmethod sendmsg ((socket %zmq::socket) (data message)
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
	   (type %zmq::socket socket)
	   (type message data)
	   (inline sendmsg))
  (with-eintr-retry eintr-retry
    (%zmq:sendmsg (slot-value socket '%zmq::ptr)
		  (msg-t-ptr data)
		  (if send-more %zmq::+sndmore+ 0))))

(defmethod sendmsg ((socket %zmq::socket) (data function)
		    &key (send-more nil) (eintr-retry t))
  (declare (type (boolean) send-more eintr-retry)
	   (type %zmq::socket socket)
	   (type (function (message &optional (or null symbol))
			   (values t t)) data)
	   (inline sendmsg))
  (with-message (msg)
    (multiple-value-bind (msg more)
	(funcall data msg)
      (if more
	  (progn
	    (sendmsg socket msg :send-more t :eintr-retry eintr-retry)
	    (sendmsg socket data :send-more send-more :eintr-retry eintr-retry))
	  (sendmsg socket msg :send-more send-more :eintr-retry eintr-retry)))))

(defgeneric recvmsg (socket message &key blocking as eintr-retry))

(defmethod recvmsg (socket (message message)
		    &key (blocking t) as (eintr-retry t))
  (declare (type (boolean) eintr-retry blocking)
	   (type message message)
	   (type (or null symbol) as)
	   (type %zmq::socket socket)
	   (inline recvmsg))
  (with-eintr-retry eintr-retry
    (%zmq:recvmsg (slot-value socket '%zmq::ptr)
		  (msg-t-ptr message)
		  (if blocking 0 %zmq::+dontwait+)))
  (when as (change-class message as))
  message)

(defmethod recvmsg (socket (message (eql :string))
		    &key (blocking t) as (eintr-retry t))
  (declare (ignore as)
	   (type %zmq::socket socket)
	   (inline recvmsg))
  (with-message (msg)
    (data (recvmsg socket msg :as 'string-message
			      :blocking blocking
			      :eintr-retry eintr-retry))))

(defmethod recvmsg (socket (message (eql :octet))
		    &key (blocking t) as (eintr-retry t))
  (declare (ignore as)
	   (type %zmq::socket socket)
	   (inline recvmsg))
  (with-message (msg)
    (data (recvmsg socket msg :as 'octet-message
			      :blocking blocking
			      :eintr-retry eintr-retry))))

(defun make-message-future (socket &key (blocking t) (eintr-retry t))
  (let ((more t))
    (lambda (msg &key as)
      (if more
	  (progn
	    (recvmsg socket msg :as as
				:blocking blocking
				:eintr-retry eintr-retry)
	    (setf more (%zmq:rcvmore socket))
	    (values msg more))
	  (values nil nil)))))

(defmacro has-more-p (future)
  `(multiple-value-bind (msg more)
       ,future
     (declare (ignore msg))
     more))

(defmacro with-message-future ((sym socket
				&key (blocking t) (eintr-retry t))
			       &body body)
  (alexandria:with-gensyms (more)
    `(let ((,more t))
       (flet ((,sym (msg &key as)
		(if ,more
		    (progn
		      (let ((res (recvmsg ,socket msg
					  :as as
					  :blocking ,blocking
					  :eintr-retry ,eintr-retry)))
			(setf ,more (%zmq:rcvmore ,socket))
			(values res ,more)))
		    (values nil nil))))
	 (progn
	   ,@body)))))

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
