(defpackage #:message
  (:documentation "Message API")
  (:use #:common-lisp)
  (:export
   #:with-message
   #:make-message
   #:close-message
   #:free-message
   #:destroy-message
   #:octet-message
   #:string-message
   #:as-string-message
   #:as-octet-message
   #:binary-address-to-string
   #:message
   #:size
   #:data
   #:msg-t
   #:msg-t-ptr))

(in-package #:message)

(declaim (optimize (speed 3)))

;;; Standard message
(defclass message ()
  ((msg-t
    :reader msg-t-ptr)
   (data
    :accessor data))
  (:documentation "Class: message
Class precedence: t
Message Base Class. Can be use to access the raw data pointer"))

(defmethod print-object ((message message) stream)
  (change-class message 'octet-message)
  (format stream "ZeroMQ Message ~A~%" (msg-t-ptr message))
  (format stream "Message length: ~A:~%" (%zmq::msg-size (msg-t-ptr message)))
  (format stream "Message data: ~A:~%" (data message)))

(defmethod data ((message message))
  "Get raw data pointer from message"
  (%zmq::msg-data (msg-t-ptr message)))


(defmethod (setf data) (data (message message))
  "Set raw data pointer for message. Uses memcpy."
  (with-slots ((msg-t msg-t))
      message
    (let ((size (%zmq::msg-size msg-t)))
      (%zmq::memcpy (%zmq::msg-data msg-t) data size))
    data))

(defmethod initialize-instance ((message message)
                                &key (size nil))
  (declare (type (or fixnum null) size))
  (setf (slot-value message 'msg-t) (cffi:foreign-alloc '(:struct %zmq::msg-t)))
  (cond
    (size
     (%zmq::msg-init-size (msg-t-ptr message) size))
    (t (%zmq::msg-init (msg-t-ptr message)))))

(declaim (ftype (function (message) fixnum) size)
         (inline size))
(defun size (msg)
  "Get message size in bytes"
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

;;; String Message

(define-condition non-null-terminate-string-error (error)
  ((message :initarg :message
            :reader message))
  (:report (lambda (condition stream)
             (format stream "A non-null terminate string-message was received.~%")
             (format stream "~A~%" (message condition)))))

(defclass string-message (message)
  ()
  (:documentation "Class: string-message
Class precedence: message
Message data as string"))

(defmethod data ((message string-message))
  "Get message data as string"
  (with-slots ((msg-t msg-t))
      message
    (let* ((ptr (%zmq::msg-data msg-t))
           (end-octet (cffi:mem-aref ptr :char (1- (%zmq::msg-size msg-t)))))
      (if (= end-octet (char-code #\null))
          (cffi:foreign-string-to-lisp ptr)
          (error (make-condition 'non-null-terminate-string-error :message message))))))

(defmethod (setf data) ((data string) (message message))
  "Set message data from string"
  (with-slots ((msg-t msg-t))
      message
    (let ((message-size (1+ (length data))))
      (%zmq::msg-close msg-t)
      (%zmq::msg-init-size msg-t message-size)
      (cffi:lisp-string-to-foreign data (%zmq::msg-data msg-t) message-size))
    data))

(defmethod initialize-instance :around ((message string-message)
                                        &key string)
  (declare (type (string) string))
  (let ((message-size (1+ (length string))))
    (call-next-method message :size message-size)
    (cffi:lisp-string-to-foreign string (%zmq::msg-data (msg-t-ptr message)) message-size)))

;;; Octet Message

(defclass octet-message (message)
  ()
  (:documentation "Class: octet-message
Class precedence: message
Message data as octets"))

(defmethod data ((message octet-message))
  "Get message data as octet array"
  (with-slots ((msg-t msg-t))
      message
    (let ((message-size (%zmq::msg-size msg-t))
          (ptr (%zmq::msg-data msg-t)))
      (declare (type fixnum message-size))
      (let ((array (make-array message-size :element-type '(unsigned-byte 8))))
        (dotimes (index message-size)
          (setf (aref array index) (cffi:mem-aref ptr :uchar index)))
        array))))

(defmethod (setf data) ((data vector) (message message))
  "Set message data from octet array"
  (declare (type (simple-array (unsigned-byte 8) (*)) data))
  (with-slots ((msg-t msg-t))
      message
    (let ((message-size (length data)))
      (%zmq::msg-close msg-t)
      (%zmq::msg-init-size msg-t message-size)
      (let ((ptr (%zmq::msg-data msg-t)))
        (loop :for octet :across data
              :for index  fixnum :from 0 :below most-positive-fixnum
              :do
              (setf (cffi:mem-aref ptr :uchar index) octet)))
      data)))

(defmethod initialize-instance :around ((message octet-message) &key octets)
  (declare (type (simple-array (unsigned-byte 8) (*)) octets))
  (call-next-method message :size (length octets))
  (let ((ptr (%zmq::msg-data (msg-t-ptr message))))
    (loop :for octet :across octets
          :for index fixnum :from 0 :below most-positive-fixnum
          :do
          (setf (cffi:mem-aref ptr :uchar index) octet))))

;;; Message Cleanup
(defgeneric close-message (message)
  (:documentation "Close message"))
(defgeneric free-message (message)
  (:documentation "Free message pointer"))
(defgeneric destroy-message (message)
  (:documentation "Destroy message calling close and free"))


(defmethod close-message ((message message))
  (%zmq::msg-close (msg-t-ptr message)))

(defmethod free-message ((message message))
  (cffi:foreign-free (msg-t-ptr message)))

(defmethod close-message ((message cons))
  (%zmq::msg-close (msg-t-ptr (car message)))
  (when (cdr message)
    (close-message (cdr message))))

(defmethod free-message ((message cons))
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
(defgeneric make-message (data)
  (:documentation "Make message"))

(defun make-zero-copy-message (data size &optional hint)
  (declare (type fixnum size))
  (make-instance 'zero-copy-message
                 :data data :size size :hint hint))

(defmethod make-message ((data integer))
  (make-instance 'message :size data))

(defmethod make-message ((data (eql nil)))
  (make-instance 'message))

(defmethod make-message ((data string))
  (declare (type (string) data))
  (make-instance 'string-message :string data))

(defmethod make-message ((data vector))
  (declare (type (vector (unsigned-byte 8))))
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
  "Macro: with-message
Binds a message object to symbol argument MSG setting with optional data DATA."
  `(let ((,msg (make-message ,data)))
     (declare (type message ,msg))
     (unwind-protect
          (progn
            ,@body)
       (destroy-message ,msg))))

(defmacro with-messages (message-list &body body)
  "Macro: with-messages
Binds multi messages declared in lambda-lists of message-list in the form (MSG &optional DATA)"
  (if message-list
      `(with-message ,(car message-list)
         (with-messages ,(cdr message-list)
           ,@body))
      `(progn ,@body)))


;;; Helpers

(defun as-string-message (msg)
  "Return MSG as class string-message"
  (change-class msg 'string-message))

(defun as-octet-message (msg)
  "Return MSG as class octet-message"
  (change-class msg 'octet-message))

(defun binary-address-to-string (message)
  (let ((message (change-class message 'octet-message)))
    (format nil "~{~X~}" (data message))))
