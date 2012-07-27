
(defpackage #:zguide.chapter-2
  (:nicknames #:chapter-2)
  (:use #:common-lisp)
  (:export))

(in-package zguide.chapter-2)

(defun msreader ()
  (zmq:with-context (ctx)
    (zmq:with-sockets ((receiver ctx :pull :connect "tcp://localhost:5557")
		       (subscriber ctx :sub :connect "tcp://localhost:5556"))
      (setf (zmq:subscribe subscriber) "10001 ")
      (zmq:with-message (msg)
	(loop
	 (loop
	  (restart-case
	      (handler-bind ((zmq:eagain
			      #'(lambda (condition)
				  (declare (ignore condition))
				  (invoke-restart 'stop-processing))))
		(zmq:recvmsg receiver msg :blocking nil))
	    (stop-processing () (return))))
	 (loop
	  (restart-case
	      (handler-bind ((zmq:eagain
			      #'(lambda (condition)
				  (declare (ignore condition))
				  (invoke-restart 'stop-processing))))
		(zmq:recvmsg subscriber msg :blocking nil))
	    (stop-processing () (return))))
	 (sleep 1))))))

(defun run-msreader ()
  (let ((weather-server (bt:make-thread #'chapter-1::weather-server
					:name "Weather Server")))
    (msreader)))

(defun mspoller ()
  (zmq:with-context (ctx)
    (zmq:with-sockets ((receiver ctx :pull :connect "tcp://localhost:5557")
		       (subscriber ctx :sub :connect "tcp://localhost:5556"))
      (setf (zmq:subscribe subscriber) "10001 ")
      (zmq:with-poll-list (poll-list (recv-item receiver :pollin)
				     (sub-item subscriber :pollin))
	(zmq:with-message (msg)
	  (loop
	   (when (zmq:poll poll-list)
	     (when (zmq:has-events-p recv-item)
	       (zmq:recvmsg receiver msg))
	     (when (zmq:has-events-p sub-item)
	       (zmq:recvmsg subscriber msg)))))))))