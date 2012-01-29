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
				&key (size nil))
  (declare (type (or fixnum null) size))
  (setf (slot-value message 'msg-t) (cffi:foreign-alloc '%zmq::msg-t))
  (cond
    (size
     (%zmq::msg-init-size (msg-t-ptr message) size))
    (t (%zmq::msg-init (msg-t-ptr message)))))

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
					  hint)
  (call-next-method message)
  (%zmq::msg-init-data (msg-t-ptr message)
		       data
		       size
		       free-fn
		       hint))

(defun reset-message (message &optional new-size)
  (declare (inline reset-message)
	   (type (or null fixnum) new-size))
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
    (let ((len (%zmq::msg-size msg-t))
	  (ptr (%zmq::msg-data msg-t)))
      (declare (type fixnum len))
      (let ((array (make-array len :element-type '(unsigned-byte 8))))
	(dotimes (index len)
	  (setf (aref array index) (cffi:mem-aref ptr :uchar index)))
	array))))

(defmethod (setf data) ((data vector) (message message))
  (declare (type (simple-array (unsigned-byte 8) (*)) data))
  (let ((len (length data)))
    (reset-message message len)
    (let ((ptr (%zmq:msg-data (msg-t-ptr message))))
      (loop :for octet :across data
	    :for index  fixnum :from 0 :below most-positive-fixnum
	    :do
	    (setf (cffi:mem-aref ptr :uchar index) octet)))
    data))

(defmethod initialize-instance :around ((message octet-message) &key octets)
  (declare (type (simple-array (unsigned-byte 8) (*)) octets))
  (call-next-method message :size (length octets))
  (let ((ptr (%zmq:msg-data (msg-t-ptr message))))
    (loop :for octet :across octets
	  :for index fixnum :from 0 :below most-positive-fixnum
	  :do
	  (setf (cffi:mem-aref ptr :uchar index) octet))))

;;; Message Cleanup
(defgeneric close-message (message))
(defgeneric free-message (message))
(defgeneric destroy-message (message))

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

(defmethod destroy-message ((message message))
  (close-message message)
  (free-message message))

(defmethod destroy-message ((message cons))
  (destroy-message (car message))
  (when (cdr message)
    (destroy-message (cdr message))))

;;; Make message interface

(defgeneric make-message (data))

(defun make-zero-copy-message (data size &optional hint)
  (declare (inline make-zero-copy-message)
	   (type fixnum size))
  (make-instance 'zero-copy-message
		 :data data :size size :hint hint))

(defmethod make-message ((data integer))
  (declare (inline make-message))
  (make-instance 'message :size data))

(defmethod make-message ((data (eql nil)))
  (declare (inline make-message))
  (make-instance 'message))

(defmethod make-message ((data string))
  (declare (inline make-message)
	   (type (string) data))
  (make-instance 'string-message :string data))

(defmethod make-message ((data vector))
  (declare (inline make-message)
	   (type (vector (unsigned-byte 8))))
  (make-instance 'octet-message :octets data))

(defmethod make-message ((data cons))
  (let ((result (list (make-message (car data)))))
    (when (cdr data)
      (setf result (append result (make-message (cdr data)))))
    result))

;;; Interface methods

(defun copy-message (destination source)
  (%zmq::msg-copy (msg-t-ptr destination) (msg-t-ptr source)))

(defmacro with-message ((msg &optional data) &body body)
  `(let ((,msg (make-message ,data)))
     (declare (type message ,msg))
     (unwind-protect
	  (progn
	    ,@body)
       (destroy-message ,msg))))

(defmacro with-messages (message-list &body body)
  (if message-list
      `(with-message ,(car message-list)
	 (with-messages ,(cdr message-list)
	   ,@body))
      `(progn ,@body)))

;;; Helpers

(defun as-string-message (msg)
  (change-class msg 'string-message))

(defun as-octet-message (msg)
  (change-class msg 'octet-message))

(defun binary-address-to-string (message)
  (let ((message (change-class message 'octet-message)))
    (format nil "~{~X~}" (data message))))

#++(defun unwra (msg-list)
  (let ((address (pop msg-list)))
    (when (zerop (size (first msg-list)))
      (pop msg-list))
    address))

(defun wrap (address msg-list)
  (append (list address) (append (list (make-message 0))
				 (alexandria:ensure-list msg-list))))