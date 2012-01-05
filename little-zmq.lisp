(in-package #:little-zmq)

(defclass message ()
  ((msg-t
    :reader msg-t-ptr)))

(defmethod initialize-instance :after ((message message))
  (%zmq::msg-init (msg-t-ptr message)))

(defclass zero-copy-message ()
  ((free-fn
    :reader free-fn
    :initarg :free-fn
    :initform '%zmq::cffi-alloc-free-fn)))

(defmethod initialize-instance :after ((message zero-copy-message)
				       &key data size hint)
  (%zmq::msg-init-data (msg-t-ptr message)
		       data
		       size
		       (free-fn message)
		       hint))

(defclass string-message (message)
  ())

(defun make-message (&optional size)
  (make-instance 'message))

(defun make-string-message (string)
  (declare (ignore string))
  (make-instance 'message))

(defun make-zero-copy-message (data size &optional hint)
  (make-instance 'zero-copy-message
		 :data data :size size :hint hint))

(defmacro with-context ((ctx &optional (io-threads 0)) &body body)
  `(let ((,ctx (%zmq:init ,io-threads)))
     (unwind-protect
	  ,@body
       (%zmq:term ,ctx))))

(defmacro with-socket ((skt ctx type) &body body)
  `(let* ((,skt (%zmq:make-socket ,ctx
				  ,(macroexpand `(%zmq:kwsym-value ,type)))))
     (unwind-protect
	  ,@body
       (%zmq:close-socket ,skt))))

(defmacro with-sockets (socket-list &body body)
  (if socket-list
      `(with-socket ,(car socket-list)
	 (with-sockets ,(cdr socket-list)
	   ,@body))
      `(progn ,@body)))

(defmethod sendmsg ((socket %zmq::socket) (data sb-sys:system-area-pointer) &key (send-more nil))
  (let ((msg (make-zero-copy-message data 0)))
    (sendmsg socket msg :send-more send-more)))

(defmethod sendmsg ((socket %zmq::socket) (data string) &key (send-more nil))
  (let ((msg (make-string-message data)))
    (sendmsg socket msg :send-more send-more)))

(defmethod sendmsg ((socket %zmq::socket) (data message) &key (send-more nil))
  (%zmq:sendmsg (slot-value socket 'ptr)
		(slot-value data 'msg-t)
		(if send-more (%zmq:kwsym-value :sndmore) 0)))

(defmethod)

(defmethod recvmsg ((socket %zmq::socket) &key (blocking t) (message-type 'message))
  (let ((msg (make-instance message-type)))
    (%zmq:recvmsg (slot-value socket 'ptr)
		  (slot-value msg 'msg-t)
		  (if blocking 0 (%zmq:kwsym-value :dontwait)))
    msg))

(defun test ()
  (with-context (ctx)
    (with-socket (skt ctx :pull)
      (print (setf (%zmq:identity skt) "test"))
      (print (%zmq:identity skt)))))