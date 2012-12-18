(defpackage #:context
  (:documentation "Context API")
  (:use #:common-lisp)
  (:export
   #:ptr
   #:destroy
   #:context
   #:with-context))

(in-package #:context)

(defparameter +io-threads+ 1)
(defparameter +max-sockets+ 2)

(defparameter +io-threads-default+ 1)
(defparameter +max-sockets-default+ 1024)

(defclass context ()
  ((io-threads :accessor io-threads)
   (max-sockets :accessor max-sockets)
   (ptr :reader ptr)))

(defmethod (setf io-threads) (value (context context))
  (assert (integerp value) nil
          "setf context io-threads requires integer VALUE" )
  (%zmq::ctx-set (slot-value context 'ptr) +io-threads+ value))

(defmethod (setf max-sockets) (value (context context))
  (assert (integerp value) nil
          "setf context max-sockets requires integer VALUE" )
  (%zmq::ctx-set (slot-value context 'ptr) +max-sockets+ value))

(defmethod io-threads ((context context))
  (%zmq::ctx-get (slot-value context 'ptr) +io-threads+))

(defmethod max-sockets ((context context))
  (%zmq::ctx-get (slot-value context 'ptr) +max-sockets+))

(defun destroy (context)
  (%zmq::ctx-destroy (slot-value context 'ptr)))

(defmethod initialize-instance ((context context) &key
                                (io-threads +io-threads-default+)
                                (max-sockets +max-sockets-default+))
  (setf (slot-value context 'ptr) (%zmq::ctx-new))
  (setf (io-threads context) io-threads)
  (setf (max-sockets context) max-sockets))

(defmacro with-context ((ctx &key
                             (io-threads +io-threads-default+)
                             (max-sockets +max-sockets-default+))
                        &body body)
  `(let ((,ctx (make-instance 'context
                              :io-threads ,io-threads
                              :max-sockets ,max-sockets)))
     (unwind-protect
          (progn
            ,@body)
       (destroy ,ctx))))