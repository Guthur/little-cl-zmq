
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
           (zmq:receive-message responder msg)
           (format out "Received Hello~%"))
         (sleep 1)
         (zmq:with-message (msg "World")
           (zmq:send-message responder msg)))))))

(defun hello-world-client ()
  (format t "Connecting to hello world server...~%")
  (zmq:with-context (ctx)
    (zmq:with-socket (requester ctx :req :connect "tcp://localhost:5555")
      (loop :for request-number :below 10 :do
       (zmq:with-message (msg "Hello")
         (format t "Sending Hello ~s...~%" request-number)
         (zmq:send-message requester msg))
       (zmq:with-message (msg)
         (zmq:receive-message requester msg)
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
         (zmq:send-message publisher (format nil "~5,'0d ~d ~d" zipcode
                                        temperature relhumidity)))))))

(defun weather-client ()
  (zmq:with-context (ctx)
    (zmq:with-socket (subscriber ctx :sub :connect "tcp://localhost:5556")
      (format t "Collecting updates from weather server...~%")
      (let ((filter "10001"))
        (setf (zmq:subscribe subscriber) filter)
        (loop
         :for update-number :below 100
         :with total-temp = 0
         :do
         (destructuring-bind (zipcode temperature relhumidity)
             (ppcre:split " " (zmq:receive-message subscriber :string))
           (declare (ignore zipcode relhumidity))
           (incf total-temp (read-from-string temperature)))
         :finally
         (format t "Average temperature for zipcode ~D was ~D"
                 filter (/ total-temp update-number)))))))


(defun run-weather-server ()
  (let ((server (bt:make-thread #'weather-server
                                :name "Weather Server")))
    (weather-client)
    (bt:destroy-thread server)))

(let ((out *standard-output*))
  (defun taskwork ()
    (zmq:with-context (ctx)
      (zmq:with-sockets ((receiver ctx :pull :connect "tcp://localhost:5557")
                         (sender ctx :push :connect "tcp://localhost:5558"))
        (loop
         (let ((string (zmq:receive-message receiver :string)))
           (format out "~A." string)
           (sleep (/ (read-from-string string) 1000.0))
           (zmq:send-message sender "")))))))

(let ((out *standard-output*))
  (defun tasksink ()
    (zmq:with-context (ctx)
      (zmq:with-socket (receiver ctx :pull :bind "tcp://*:5558")
        (zmq:receive-message receiver :string)
        (loop
         :for task-number :below 100
         :with start-time = (get-internal-real-time)
         :do
         (zmq:receive-message receiver :string)
         (if (zerop (mod task-number 10))
             (format out ":")
             (format out "."))
         :finally (format out "Total elapsed time: ~D msec~%"
                          (- (get-internal-real-time) start-time)))))))

(defun ventilator ()
  (zmq:with-context (ctx)
    (zmq:with-sockets ((sender ctx :push :bind "tcp://*:5557")
                       (sink ctx :push :connect "tcp://localhost:5558"))
      (format t "Press any key when the workers are ready: ~%")
      (read-char)
      (format t "Sending tasks to workers...~%")
      (zmq:send-message sink "0")      
      (loop
       :for task-number :below 100
       :with total-msec = 0 :do
       (let ((workload (1+ (random 100))))
         (incf total-msec workload)
         (zmq:send-message sender (format nil "~D" workload)))
       :finally (format t "Total expected cost: ~D msec~%" total-msec))
      (sleep 1))))

(defun run-parallel-pipeline (&optional (worker-count 1))
  (let ((workers (loop
                  :for count :below worker-count
                  :collect (bt:make-thread #'taskwork
                                           :name (format nil "Worker-~D"
                                                         (1+ count)))))
        (sink (bt:make-thread #'tasksink :name "Sink")))
    (ventilator)
    (bt:join-thread sink)
    (map nil #'bt:destroy-thread workers)))