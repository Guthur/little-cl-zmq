(in-package #:little-zmq)

(defun call-with-retry (predicate thunk)
  (declare (inline call-with-retry))
  (declare (type (function (condition) boolean) predicate)
	   (type (function nil) thunk))
  (tagbody retry
     (return-from call-with-retry
       (handler-bind ((t (lambda (condition)			   
                           (when (funcall predicate condition)
                             (go retry)))))
         (funcall thunk)))))

(defmacro with-zmq-eintr-retry (&optional (active t) &body body)
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