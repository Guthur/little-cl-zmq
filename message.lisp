(in-package #:little-zmq)


;;; Standard message
(defclass message ()
  ((msg-t
    :reader msg-t-ptr)
   (data
    :accessor data)))

(defmethod data ((message message))
  (with-slots ((msg-t msg-t))
      message
    (let* ((size (%zmq:msg-size msg-t))
	   (ptr (cffi:foreign-alloc :char :count size)))
      (%zmq::memcpy ptr (%zmq:msg-data msg-t) size)
      ptr)))

(defmethod (setf data) (data (message message))
  (with-slots ((msg-t msg-t))
      message
    (let ((size (%zmq:msg-size msg-t)))
      (%zmq::memcpy (%zmq:msg-data msg-t) data size))
    data))

(defmethod initialize-instance ((message message)
				&key size)
  (declare (type (or (integer 0) null) size))
  (let ((ptr (cffi:foreign-alloc '%zmq::msg-t)))
    (tg:finalize message (lambda ()
			   (%zmq:msg-close ptr)
			   (cffi:foreign-free ptr)))
    (setf (slot-value message 'msg-t) ptr)
    (cond
      (size
       (%zmq::msg-init-size (msg-t-ptr message) size))
      (t (%zmq::msg-init (msg-t-ptr message))))))

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

;;; String Message

(defclass string-message (message)
  ())

(defmethod data ((message string-message))
  (with-slots ((msg-t msg-t))
      message
    (cffi:foreign-string-to-lisp (%zmq:msg-data msg-t))))

(defmethod (setf data) (data (message string-message))
  (with-slots ((msg-t msg-t))
      message
    (cffi:with-foreign-string (str data)
      (call-next-method str message))))

(defmethod initialize-instance :around ((message string-message)
					&key string (null-terminated-p t))
  (declare (type (string) string))
  (call-next-method message
		    :size (+ (length string)
			     (if null-terminated-p 1 0)))
  (cffi:lisp-string-to-foreign string (%zmq:msg-data (msg-t-ptr message))
			       (+ (length string)
				  (if null-terminated-p 1 0))))

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
	(setf (aref array index) (cffi:mem-aref ptr :char index)))
      array)))

(defmethod initialize-instance :around ((message octet-message) &key octets)
  (declare (type (vector (unsigned-byte 8)) octets))
  (call-next-method message :size (length octets))
  (let ((ptr (%zmq:msg-data (msg-t-ptr message))))
    (loop :for octet :across octets
	  :for index :from 0 :do
	    (setf (cffi:mem-aref ptr :uchar index) octet))))

;;; Make message interface

(defun make-message (&optional size)
  (declare (inline make-message)
	   (type (or (integer 0) null) size))
  (make-instance 'message :size size))

(defun make-string-message (string)
  (declare (inline make-string-message)
	   (type (string) string))
  (make-instance 'string-message :string string))

(defun make-zero-copy-message (data size &optional hint)
  (declare (inline make-zero-copy-message)
	   (type (integer 0) size))
  (make-instance 'zero-copy-message
		 :data data :size size :hint hint))

(defun make-octet-message (data)
  (declare (inline make-octet-message)
	   (type (vector (unsigned-byte 8))))
  (make-instance 'octet-message :octets data))
