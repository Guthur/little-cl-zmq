
(defpackage #:zguide.chapter-1
  (:nicknames #:chapter-1)
  (:use #:common-lisp)
  (:export #:hello-world))

(in-package zguide.chapter-1)


(let ((out *standard-output*))
  (defun hello-world-server ()
    (zmq:with-context (ctx)
      (zmq:with-socket (responder ctx :rep :bind "tcp://*:5555")
	(loop
	 (zmq:with-message (msg)
	   (zmq:recvmsg responder msg)
	   (format out "Received Hello~%"))
	 (sleep 1)
	 (zmq:with-message (msg "World")
	   (zmq:sendmsg responder msg)))))))

(defun hello-world-client ()
  (format t "Connecting to hello world server...~%")
  (zmq:with-context (ctx)
    (zmq:with-socket (requester ctx :req :connect "tcp://localhost:5555")
      (loop :for request-number :below 10 :do
       (zmq:with-message (msg "Hello")
	 (format t "Sending Hello ~s...~%" request-number)
	 (zmq:sendmsg requester msg))
       (zmq:with-message (msg)
	 (zmq:recvmsg requester msg)
	 (format t "Received World ~s~%" request-number))))))

(defun run-hello-world ()
  (let ((server (bt:make-thread #'hello-world-server
				:name "Hello World Server")))
    (hello-world-client)
    (bt:destroy-thread server)))

(defun report-version ()
  (multiple-value-bind (major minor patch)
      (zmq:version)
    (format t "Current 0MQ Version is ~d.~d.~d~%" major minor patch)))



(defun weather-server ()
  (zmq:with-context (ctx)
    (zmq:with-socket (publisher ctx :pub :bind '("tcp://*:5556"
						 "ipc://weather.ipc"))
      (loop
       (let ((zipcode (random 100000))
	     (temperature (- (random 215) 80))
	     (relhumidity (+ (random 50) 10)))
	 (zmq:sendmsg publisher (format nil "~5,'0d ~d ~d" zipcode
					temperature relhumidity)))))))

(defun weather-client ()
  (zmq:with-context (ctx)
    (zmq:with-socket (subscriber ctx :sub :connect "tcp://localhost:5556")
      (format t "Collecting updates from weather server...~%")
      (setf (zmq:subscribe subscriber) "10001")
      (zmq:with-message (msg)
	(loop
	 :for update-number :below 100 :do
	 (zmq:recvmsg subscriber msg :as 'zmq:string-message)
	 (format t "~S~%" (zmq:data msg)))))))


(defun run-weather-server ()
  (let ((server (bt:make-thread #'weather-server
				:name "Weather Server")))
    (weather-client)
    (bt:destroy-thread server)))