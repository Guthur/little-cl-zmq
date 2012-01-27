(in-package #:little-zmq)

(declaim (optimize (speed 3)))

;;; Standard message
(defclass message ()
  ((msg-t
    :reader msg-t-ptr)
   (data
    :accessor data)))

(defmethod data ((message message))
  (%zmq:msg-data (msg-t-ptr message)))


(defmethod (setf data) (data (message message))
  (with-slots ((msg-t msg-t))
      message
    (let ((size (%zmq:msg-size msg-t)))
      (%zmq::memcpy (%zmq:msg-data msg-t) data size))
    data))

(defmethod initialize-instance ((message message)
				&key (size nil) (use-finalizer t))
  (declare (type (or (integer 0) null) size))
  (let ((ptr (cffi:foreign-alloc '%zmq::msg-t)))
    (when use-finalizer
      (tg:finalize message (lambda ()
			     (%zmq:msg-close ptr)
			     (cffi:foreign-free ptr))))
    (setf (slot-value message 'msg-t) ptr)
    (cond
      (size
       (%zmq::msg-init-size (msg-t-ptr message) size))
      (t (%zmq::msg-init (msg-t-ptr message))))))

(defun size (msg)
  (%zmq::msg-size (msg-t-ptr msg)))

;;; Zero Copy Message

(defclass zero-copy-message (message)
  ((free-fn
    :reader free-fn
    :initarg :free-fn
    :initform '%zmq::cffi-free-fn)))

(defmethod initialize-instance :around ((message zero-copy-message)
					&key
					  data
					  size
					  (free-fn (cffi:get-callback
						    '%zmq::cffi-free-fn))
					  (hint (cffi:null-pointer)))
  (call-next-method message)
  (%zmq::msg-init-data (msg-t-ptr message)
		       data
		       size
		       free-fn
		       hint))

(defun reset-message (message &optional new-size)
  (declare (inline reset-message)
	   (type message message)
	   (type (or null (integer 0)) new-size))
  (close-message message)
  (if new-size
      (%zmq::msg-init-size (msg-t-ptr message) new-size)
      (%zmq::msg-init (msg-t-ptr message))))

;;; String Message

(defclass string-message (message)
  ())

(defmethod data ((message string-message))
  (with-slots ((msg-t msg-t))
      message
    (cffi:foreign-string-to-lisp (%zmq:msg-data msg-t))))

(defmethod (setf data) ((data string) (message message))
  (let ((len (1+ (length data))))
    (reset-message message len)
    (cffi:lisp-string-to-foreign data (%zmq:msg-data (msg-t-ptr message)) len))
  data)

(defmethod initialize-instance :around ((message string-message)
					&key string)
  (declare (type (string) string))
  (call-next-method message
		    :size (1+ (length string)))
  (cffi:lisp-string-to-foreign string (%zmq:msg-data (msg-t-ptr message))
			       (1+ (length string))))

;;; Octet Message

(defclass octet-message (message)
  ())

(defmethod data ((message octet-message))
  (with-slots ((msg-t msg-t))
      message
    (let* ((len (%zmq::msg-size msg-t))
	   (ptr (%zmq::msg-data msg-t))
	   (array (make-array len :element-type '(unsigned-byte 8))))
      (dotimes (index len)
	(setf (aref array index) (cffi:mem-aref ptr :uchar index)))
      array)))

(defmethod (setf data) ((data vector) (message message))
  (declare (type (vector (unsigned-byte 8)) data))
  (let ((len (length data)))
    (reset-message message len)
    (let ((ptr (%zmq:msg-data (msg-t-ptr message))))
      (loop :for octet :across data
	    :for index :from 0
	    :do
	    (setf (cffi:mem-aref ptr :uchar index) octet)))
    data))

(defmethod initialize-instance :around ((message octet-message) &key octets)
  (declare (type (vector (unsigned-byte 8)) octets))
  (call-next-method message :size (length octets))
  (let ((ptr (%zmq:msg-data (msg-t-ptr message))))
    (loop :for octet :across octets
	  :for index :from 0
	  :do
	  (setf (cffi:mem-aref ptr :uchar index) octet))))


;;; Message Cleanup

(defmethod close-message ((message message))
  (declare (inline close-message))
  (%zmq:msg-close (msg-t-ptr message)))

(defmethod free-message ((message message))
  (declare (inline free-message))
  (cffi:foreign-free (msg-t-ptr message)))

(defmethod close-message ((message cons))
  (declare (inline close-message))
  (%zmq:msg-close (msg-t-ptr (car message)))
  (when (cdr message)
    (close-message (cdr message))))

(defmethod free-message ((message cons))
  (declare (inline free-message))
  (cffi:foreign-free (msg-t-ptr (car message)))
  (when (cdr message)
    (free-message (cdr message))))

(defun destroy-message (message)
  (close-message message)
  (free-message message))

;;; Make message interface

(defun make-zero-copy-message (data size &optional hint)
  (declare (inline make-zero-copy-message)
	   (type (integer 0) size))
  (make-instance 'zero-copy-message
		 :data data :size size :hint hint))

(defmethod make-message ((data integer) &optional (use-finalizer t))
  (declare (inline make-message))
  (make-instance 'message :size data :use-finalizer use-finalizer))

(defmethod make-message ((data (eql nil)) &optional (use-finalizer t))
  (declare (inline make-message))
  (make-instance 'message :use-finalizer use-finalizer))

(defmethod make-message ((data string) &optional (use-finalizer t))
  (declare (inline make-message)
	   (type (string) data)
	   (type (boolean) use-finalizer))
  (make-instance 'string-message :string data :use-finalizer use-finalizer))

(defmethod make-message ((data vector) &optional (use-finalizer t))
  (declare (inline make-message)
	   (type (vector (unsigned-byte 8))))
  (make-instance 'octet-message :octets data :use-finalizer use-finalizer))

(defmethod make-message ((data cons) &optional (use-finalizer t))
  (let ((result (list (make-message (car data) use-finalizer))))
    (when (cdr data)
      (setf result (append result (make-message (cdr data) use-finalizer))))
    result))

;;; Interface methods

(defmethod copy-message ((destination message) (source message))
  (%zmq::msg-copy (msg-t-ptr destination) (msg-t-ptr source)))

(defmacro with-message ((msg &optional data) &body body)
  `(let ((,msg (make-message ,data nil)))
     (unwind-protect
	  (progn
	    ,@body)
       (close-message ,msg)
       (free-message ,msg))))

(defmacro with-messages (message-list &body body)
  (if message-list
      `(with-message ,(car message-list)
	 (with-messages ,(cdr message-list)
	   ,@body))
      `(progn ,@body)))

(defun pop-message (msg-list)
  (declare (ignore msg-list))
  (error "This function should only be called in the body of a \"WITH-MULTI-PART-MESSAGE\""))

(defclass msg-list ()
  ((parts
    :initform nil
    :accessor parts)))

(defun destroy-msg-list (msg-list)
  (mapcar #'destroy-message (parts msg-list)))

(defmacro with-multi-part-message (sym &body body)
  (alexandria:with-gensyms (cleanup)
    `(let ((,cleanup (make-instance 'msg-list))
	   (,sym (make-instance 'msg-list)))
       (flet ((pop-message (msg-list)
		(with-accessors ((parts parts))
		    msg-list
		  (let ((msg (pop parts)))
		    (cons msg ,cleanup)
		    msg)))
	      (unwrap (msg-list)
		(with-accessors ((msg-parts parts))
		    msg-list
		  (with-accessors ((cleanup-parts parts))
		      ,cleanup
		    (let ((msg (pop msg-parts)))
		      (when (zerop (size (first msg-parts)))
			(destroy-message (pop msg-parts)))
		      (setf cleanup-parts (cons msg cleanup-parts))
		      msg)))))
	 (declare (ignorable #'pop-message #'unwrap))
	 (unwind-protect
	      (progn
		,@body)
	   (destroy-msg-list ,cleanup)
	   (destroy-msg-list ,sym))))))

;;; Helpers

(defun as-string-message (msg)
  (change-class msg 'string-message))

(defun as-octet-message (msg)
  (change-class msg 'octet-message))

(defun uuid-address-to-string (message)
  (let ((message (change-class message 'octet-message)))
    (with-output-to-string (s)
      (format s "~{~X~}" (coerce (data message) 'cons)))))

(defun unwrap (msg-list)
  (let ((address (pop msg-list)))
    (when (zerop (size (first msg-list)))
      (pop msg-list))
    address))

(defun wrap (address msg-list)
  (append (list address) (append (list (make-message 0))
				 (alexandria:ensure-list msg-list))))