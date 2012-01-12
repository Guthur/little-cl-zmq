(in-package #:little-zmq)

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
    (with-socket ((rep ctx :rep) :connect "tcp://localhost:5559")
      (let ((msg (make-message)))
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
    (with-socket ((req ctx :req) :bind "tcp://*:5559")
      (let ((worker (bt:make-thread (make-worker ctx message-count)
				    :name "worker"))
	    (msg (make-message message-size)))
	(declare (ignore worker))
	(print (/ (/ (with-stopwatch
		       (dotimes (x message-count)			 
			 (sendmsg req msg)
			 (setf msg (recvmsg req :reuse-msg msg))))
		     1000)
		  (* message-count 2.0)))))))

(defun test ()
  (with-context (ctx)
    (with-sockets (((rep ctx :router) :bind "inproc://testa")
		   ((req ctx :req) :connect "inproc://testa"))
      (let ((msg (make-octet-message
		  (make-array 5 :element-type '(unsigned-byte 8)
				:initial-contents '(1 2 3 4 5)))))
	(sendmsg req msg)
	(let ((ret (recvall rep)))
	  (print (uuid-address-to-string (change-class (first ret) 'octet-message))))))))


(defun poll-test (msg-count)
  (with-context (ctx)
    (with-sockets (((rep ctx :rep) :bind "tcp://*:6666")
		   ((req ctx :req) :connect "tcp://localhost:6666"))
      (sleep 1)
      (sendmsg req "Request")
      (let ((count 0))
	(print
	 (with-polls (((rep :pollin
			    (lambda (skt revents)
			      (declare (ignore revents))
			      (let ((ret (recvmsg skt
						  :message-type
						  'string-message)))
				(print (data ret))
				(sendmsg skt "Rep"))))
		       (req :pollin
			    (lambda (skt revents)
			      (declare (ignore revents))
			      (let ((ret (recvmsg skt
						  :message-type
						  'string-message)))
				(print (data ret))
				(when (zerop (decf msg-count))
				  (exit-poll))
				(sendmsg skt "Request")))))
		      :timeout 1000
		      :loop t)
	   (incf count)))))))


(defun client ()
  (with-context (ctx)
    (with-socket ((req ctx :req) :connect "tcp://localhost:5559")
      (dotimes (request 10)
	(sendmsg req "Hello")
	(let ((msg (recvmsg req :message-type 'string-message)))
	  (format t "Received reply: ~a ~a.~%" request (data msg)))))))

(defun server (id)
  (lambda ()
    (with-context (ctx)
      (with-socket ((rep ctx :rep) :connect "tcp://localhost:5560")
	(loop
	 (let ((msg (recvmsg rep :message-type 'string-message)))
	   (format t "Received request: ~a" (data msg))
	   (sleep 1)
	   (sendmsg rep (with-output-to-string (s)
			  (format s "World ~a" id)))))))))

(defun broker ()
  (with-context (ctx) 
    (with-sockets (((frontend ctx :router) :bind "tcp://*:5559")
		   ((backend ctx :dealer) :bind "tcp://*:5560"))
      (flet ((frontend-handler (skt revents)
	       (declare (ignore revents))
	       (sendmsg backend (recvall skt)))
	     (backend-handler (skt revents)
	       (declare (ignore revents))
	       (sendmsg frontend (recvall skt))))
	(with-polls (((frontend :pollin #'frontend-handler)
		      (backend :pollin #'backend-handler))
		     :loop t))))))

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

#++(with-context (ctx)
  (with-sockets (((router-skt ctx :router)
		  :identity "frontend"
		  :bind "tcp://*:5555")
		 ((req-skt ctx :req)
		  :identity "frontend"
		  :bind "tcp://*:5555"))
    (sendmsg req "Hello")
    (recvall router-skt)))

#++(with-sockets ((router-skt ctx :router
			   :identity "frontend"
			   :bind "tcp://*:5555")
	       (req-skt ctx :req
			:identity "frontend"
			:bind "tcp://*:5555"))
  (sendmsg req "Hello")
  (recvall router-skt))



(defun test-router ()
  (with-context (ctx)
    (with-sockets (((frontend ctx :router) :bind "tcp://*:20006")
		   ((req ctx :req) :connect "tcp://localhost:20006"))
      (sendmsg req (make-octet-message (make-array 5
						   :element-type '(unsigned-byte 8)
						   :initial-contents '(1 2 3 4 5))))
      (recvmsg frontend :message-type 'octet-message)
      (recvmsg frontend)
      (print (data (recvmsg frontend :message-type 'octet-message))))))