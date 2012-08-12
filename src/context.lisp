(defpackage #:context
  (:documentation "Context API")
  (:use #:common-lisp)
  (:export
   #:ptr
   #:destroy
   #:context
   #:with-context
   #:activate-monitoring))

(in-package #:context)

(defparameter +io-threads+ 1)
(defparameter +max-sockets+ 2)

(defparameter +io-threads-default+ 1)
(defparameter +max-sockets-default+ 1024)

(defmacro define-context-events (events)
  (let ((event-id 1))
    `(progn ,@(loop :for symbol :in events
	       :collect (list 'defparameter symbol event-id)
	       :do (setf event-id (* event-id 2))))))

(define-context-events
    (+event-connected+
     +event-connect-delayed+
     +event-connect-retried+
     +event-listening+
     +event-bind-failed+
     +event-accepted+
     +event-accept-failed+
     +event-closed+
     +event-close-failed+
     +event-disconnected+))

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
       (%zmq::ctx-set-monitor (ptr ,ctx) (cffi:null-pointer))
       (destroy ,ctx))))

(cffi:defcstruct event-data-t
  (address :string)
  (data :int))

(defun activate-monitoring (context)
  (%zmq::ctx-set-monitor (ptr context) (cffi:callback ctx-monitor-callback)))

(cffi:defcallback ctx-monitor-callback :void
    ((socket :pointer)
     (event :int)
     (data :pointer event-data-t))
  (declare (ignore socket data))
  (unless (zerop (boole boole-and event +event-connected+))
    (format t "Connected~%"))
  (unless (zerop (boole boole-and event +event-connect-delayed+))
    (format t "Connect delayed~%"))
  (unless (zerop (boole boole-and event +event-connect-retried+))
    (format t "Connect retried~%"))
  (unless (zerop (boole boole-and event +event-listening+))
    (format t "Listening~%"))
  (unless (zerop (boole boole-and event +event-bind-failed+))
    (format t "Bind failed~%"))
  (unless (zerop (boole boole-and event +event-accepted+))
    (format t "Accepted~%"))
  (unless (zerop (boole boole-and event +event-accept-failed+))
    (format t "Accept failed~%"))
  (unless (zerop (boole boole-and event +event-closed+))
    (format t "Close~%"))
  (unless (zerop (boole boole-and event +event-close-failed+))
    (format t "Close failed~%"))
  (unless (zerop (boole boole-and event +event-disconnected+))
    (format t "Disconnected~%")))

