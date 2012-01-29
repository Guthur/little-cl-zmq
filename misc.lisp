(in-package #:little-zmq)

(declaim (optimize (speed 3)))

(defun call-with-retry (predicate thunk)
  (declare (inline call-with-retry)
	   (type (function nil) thunk)
	   (type (function (error) boolean) predicate))
  (tagbody retry
     (return-from call-with-retry
       (handler-bind ((t (lambda (condition)			   
                           (when (funcall predicate condition)
                             (go retry)))))
         (funcall thunk)))))

(defmacro with-eintr-retry (&optional (active t) &body body)
  `(if ,active
       (call-with-retry
	(lambda (condition)
	  (and (typep condition '%zmq::zmq-error)
	       (eql (%zmq::error-number condition)
		    %zmq::+eintr+)))
	(lambda ()
	  ,@body))
       (progn
	 ,@body)))