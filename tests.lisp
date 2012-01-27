(in-package #:little-zmq)

(declaim (optimize (speed 3)))

(cffi:defcstruct time-spec
  "Time Spec"
  (seconds :int)
  (nano :long))

(cffi:defcfun "clock_getres" :int
  "Get clock precision"
  (clock-id :int)
  (timespec :pointer))

(cffi:defcfun "clock_gettime" :int
  "Get clock time"
  (clock-id :int)
  (timespec :pointer))

(cffi:defcfun "clock_settime" :int
  "Set clock time"
  (clock-id :int)
  (timespec :pointer))

(defvar clock-realtime 0)
(defvar clock-monotonic 1)
(defvar clock-process-cputime-id 2)
(defvar clock-thread-cputime-id 3)
(defvar clock-monotonic-raw 4)
(defvar clock-realtime-coarse 5)
(defvar clock-monotonic-coarse 6)
(defvar clock-boottime 7)
(defvar clock-realtime-alarm 8)

(defun get-clock-time (clock-id)
  (cffi:with-foreign-object (tspec 'time-spec)
    (let ((ret (clock-gettime clock-id tspec)))
      (if (zerop ret)
	  (values (cffi:foreign-slot-value tspec 'time-spec 'seconds)
		  (cffi:foreign-slot-value tspec 'time-spec 'nano))
	  (error "Error raise in C call")))))

(defun set-clock-time (clock-id seconds nano-seconds)
  (cffi:with-foreign-object (tspec 'time-spec)
    (setf (cffi:foreign-slot-value tspec 'time-spec 'seconds) seconds
	  (cffi:foreign-slot-value tspec 'time-spec 'nano) nano-seconds)
    (unless (zerop (clock-settime clock-id tspec))
      (error "Error raised in C call"))))

(defun get-clock-res (clock-id)
  (cffi:with-foreign-object (tspec 'time-spec)
    (let ((ret (clock-getres clock-id tspec)))
      (if (zerop ret)
	  (values (cffi:foreign-slot-value tspec 'time-spec 'seconds)
		  (cffi:foreign-slot-value tspec 'time-spec 'nano))
	  (error "Error raise in C call")))))


(defun make-worker (ctx message-count)
  (declare (type fixnum  message-count))
  (lambda ()
    (with-socket (rep ctx :rep :connect "inproc://lat-test")
      (with-message (msg)
	(dotimes (i message-count)
	  (with-zmq-eintr-retry
	      (sendmsg rep (recvmsg rep :reuse-msg msg))))))))

(defmacro with-stopwatch (&body body)
  (alexandria:with-gensyms (ips)
    `(let* ((,ips (expt 10 9)))
       (multiple-value-bind (sec nano)
	   (get-clock-time clock-realtime)
	 ,@body	 
	 (multiple-value-bind (esec enano)
	     (get-clock-time clock-realtime)  
	   (+ (* ,ips (- esec sec)) (- enano nano)))))))

(defun inproc-lat (message-size message-count)
  (declare (type fixnum message-size message-count))
  (with-context (ctx 1)
    (with-socket (req ctx :req
		      :bind "inproc://lat-test")
      (let ((worker (bt:make-thread (make-worker ctx message-count)
				    :name "worker")))
	(declare (ignore worker))
	(with-message (msg message-size)
	  (print (/ (/ (with-stopwatch
			 (dotimes (x message-count)			 
			   (sendmsg req msg)
			   (setf msg (recvmsg req :reuse-msg msg))))
		       1000)
		    (* message-count 2.0))))))))


(defun test ()
  (with-context (ctx)
    (with-sockets ((rep ctx :router
			:identity "ROUTER"
			:bind "inproc://testa")
		   (req ctx :req
			:connect "inproc://testa"))      
      (sendmsg req "Hello")
      (with-multi-part-message msg
	(recvall rep msg)
	(print (data (as-string-message (third (parts msg)))))
	(setf (data (third (parts msg))) "World")
	(sendmsg rep (parts msg))
	(with-message (msg)
	  (print (data (recvmsg req msg :as 'string-message))))))))


(defun poll-test (msg-count)
  (with-context (ctx)
    (with-sockets ((rep ctx :rep :bind "tcp://*:6667")
		   (req ctx :req :connect "tcp://localhost:6667"))
      (sleep 1)
      (sendmsg req "Request")
      (with-poll-list (poll-list (rep-item rep :pollin)
				 (req-item req :pollin))	
	(loop
	  (when (poll poll-list 1000 t)
	    (print (has-events rep-item))
	    (when (has-events rep-item)
	      (let ((ret (recvmsg rep :as 'string-message)))
		(print (data ret))
		(sendmsg rep "Rep")))
	    (when (has-events req-item)
	      (let ((ret (recvmsg req :as 'string-message)))
		(print (data ret))
		(when (zerop (decf msg-count))
		  (return-from poll-test "finished"))
		(sendmsg req "Request")))))))))


(defun client ()
  (with-context (ctx)
    (with-socket (req ctx :req :connect "tcp://localhost:5559")
      (with-message (msg)
	(dotimes (request 10)
	  (sendmsg req (with-output-to-string (s)
			 (format s "Hello ~a" request)))
	  (recvmsg req msg :as 'string-message)
	  (format t "Received reply: ~a ~a.~%" request (data msg)))))))

(let ((out *standard-output*))
  (defun server (id)
    (lambda ()
      (with-context (ctx)
	(with-socket (rep ctx :rep :connect "tcp://localhost:5560")
	  (with-message (msg)
	    (loop
	      (recvmsg rep msg :as 'string-message)
	      (format out "Server ~a: Received request: ~S~%" id (data msg))
	      (sleep 1)
	      (setf (data msg) (with-output-to-string (s)
				 (format s "~s \"World\" from Server ~a"
					 (data msg) id)))
	      (sendmsg rep msg))))))))

(defun broker ()
  (with-context (ctx) 
    (with-sockets ((frontend ctx :router :bind "tcp://*:5559")
		   (backend ctx :dealer :bind "tcp://*:5560"))
      (with-poll-list (polls (front frontend :pollin)
			     (back frontend :pollin))
	(loop
	  (when (poll polls)
	    (when (has-events front)
	      (with-message (msg)		
		(sendmsg backend (recvall frontend))))
	    (when (has-events back)
	      (with-message (msg)		
		(sendmsg frontend (recvall backend))))))))))

(defun run-broker-test ()
  (let ((broker (bt:make-thread #'broker :name "broker"))
	(servers (loop :for x :upto 3
		       :collect
		       (bt:make-thread (server x) :name "server"))))
    (sleep 1)
    (client)
    (dolist (server servers)
      (bt:destroy-thread server))
    (bt:destroy-thread broker)))


(defun test-router ()
  (with-context (ctx)
    (with-sockets ((frontend ctx :dealer :bind "tcp://*:20006")
		   (rep ctx :rep
			:connect "tcp://localhost:20006"
			:identity "A"))
      (sendmsg frontend '("A" nil "Hello"))
      (print (data (recvmsg rep :as 'string-message))))))