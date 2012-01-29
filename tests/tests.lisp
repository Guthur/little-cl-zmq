(defpackage #:little-zmq.tests
  (:use #:cl))

(in-package #:little-zmq.tests)

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
    (zmq:with-socket (rep ctx :rep :connect "inproc://lat-test")
      (zmq:with-message (msg)
	(dotimes (i message-count)
	  (zmq:sendmsg rep (zmq:recvmsg rep msg)))))))

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
  (zmq:with-context (ctx 1)
    (zmq:with-socket (req ctx :req
		      :bind "inproc://lat-test")
      (let ((worker (bt:make-thread (make-worker ctx message-count)
				    :name "worker")))
	(declare (ignore worker))
	(zmq:with-message (msg message-size)
	  (print (/ (/ (with-stopwatch
			 (dotimes (x message-count)			 
			   (zmq:sendmsg req msg)
			   (zmq:recvmsg req msg)))
		       1000)
		    (* message-count 2.0))))))))


(defun poll-test (msg-count)
  (zmq:with-context (ctx)
    (zmq:with-sockets ((rep ctx :rep :bind "tcp://*:6667")
		       (req ctx :req :connect "tcp://localhost:6667"))
      (sleep 1)
      (zmq:sendmsg req "Request")
      (zmq:with-poll-list (poll-list (rep-item rep :pollin)
				     (req-item req :pollin))
	(zmq:with-message (msg)
	  (loop
	   (when (zmq:poll poll-list 1000 t)
	     (print (zmq:has-events-p rep-item))
	     (when (zmq:has-events-p rep-item)
	       (let ((ret (zmq:recvmsg rep msg :as 'string-message)))
		 (print (zmq:data ret))
		 (zmq:sendmsg rep "Rep")))
	     (when (zmq:has-events-p req-item)
	       (let ((ret (zmq:recvmsg req msg :as 'string-message)))
		 (print (zmq:data ret))
		 (when (zerop (decf msg-count))
		   (return-from poll-test "finished"))
		 (zmq:sendmsg req "Request"))))))))))

(defun client ()
  (zmq:with-context (ctx)
    (zmq:with-socket (req ctx :req :connect "tcp://localhost:5559")
      (zmq:with-message (msg)
	(dotimes (request 10)
	  (zmq:sendmsg req  (format nil "Hello ~a" request))
	  (zmq:recvmsg req msg :as 'string-message)
	  (format t "Received reply: ~a ~a.~%" request (zmq:data msg)))))))

(let ((out *standard-output*))
  (defun server (id)
    (lambda ()
      (zmq:with-context (ctx)
	(zmq:with-socket (rep ctx :rep :connect "tcp://localhost:5560")
	  (zmq:with-message (msg)
	    (loop
	     (let ((data (zmq:recvmsg rep :string)))	       
	       (format out "Server ~a: Received request: ~S~%" id data)
	       (sleep 1)
	       (zmq:sendmsg rep (format nil "~s \"World\" from Server ~a"
				    data id))))))))))


(let ((out *standard-output*))
  (defun broker ()
    (zmq:with-context (ctx) 
      (zmq:with-sockets ((frontend ctx :router :bind "tcp://*:5559")
		     (backend ctx :dealer :bind "tcp://*:5560"))
	(zmq:with-poll-list (polls (front frontend :pollin)
			       (back frontend :pollin))
	  (loop
	   (when (zmq:poll polls)
	     (when (zmq:has-events-p front)
	       (zmq:with-message (msg)
		 (zmq:with-message-future (front-fut frontend)		   
		   (loop :while (zmq:has-more-p (front-fut msg :as 'octet-message))
			 :do
			    (format out "Router: ~a~%" (zmq:data msg))
			    (zmq:sendmsg backend msg :send-more t)
			 :finally
			    (format out "Router: ~a~%" (zmq:data msg)))
		   (zmq:sendmsg backend msg))))
	     (when (zmq:has-events-p back)
	       (zmq:with-message-future (back-fut backend)
		 (zmq:sendmsg frontend #'back-fut))))))))))

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
  (zmq:with-context (ctx)
    (zmq:with-sockets ((frontend ctx :dealer :bind "tcp://*:20006")
		   (rep ctx :rep
			:connect "tcp://localhost:20006"
			:identity "A"))
      (zmq:sendmsg frontend '("A" nil "Hello"))
      (print (zmq:data (zmq:recvmsg frontend rep :as 'string-message))))))


(let ((out *standard-output*))
  (defun subscriber ()
    (bt:make-thread
     (lambda ()
       (zmq:with-context (ctx)
	 (zmq:with-socket (sub ctx :sub
			   :connect "tcp://localhost:20000"
			   :subscribe '("B" "A"))
	   (dotimes (x 10)
	     (zmq:with-message-future (fut sub)
	       (format out "~a~%" (fut :string))
	       (format out "~a~%" (fut :string)))
	     (setf (%zmq::unsubscribe sub) "A")))))
     :name "sub")))

(defun publisher ()
  (bt:make-thread
   (lambda ()
     (zmq:with-context (ctx)
       (zmq:with-socket (pub ctx :pub
			 :bind "tcp://*:20000")
	 (loop
	  (zmq:sendmsg pub "A" :send-more t)
	  (zmq:sendmsg pub "Hello")
	  (zmq:sendmsg pub "B" :send-more t)
	  (zmq:sendmsg pub "Hello")))))
   :name "pub"))

(defun test-sub ()
  (let ((pub (publisher))
	(sub (subscriber)))
    (sleep 10)))