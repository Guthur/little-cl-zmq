
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
                (zmq:receive-message receiver msg :blocking nil))
            (stop-processing () (return))))
         (loop
          (restart-case
              (handler-bind ((zmq:eagain
                              #'(lambda (condition)
                                  (declare (ignore condition))
                                  (invoke-restart 'stop-processing))))
                (zmq:receive-message subscriber msg :blocking nil))
            (stop-processing () (return))))
         (sleep 1))))))

(defun run-msreader ()
  (let ((weather-server (bt:make-thread #'chapter-1::weather-server
                                        :name "Weather Server")))
    (mspoller)))

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
               (zmq:receive-message receiver msg))
             (when (zmq:has-events-p sub-item)
               (zmq:receive-message subscriber msg)))))))))


(let ((out *standard-output*))
  (defun taskwork2 ()
    (zmq:with-context (ctx)
      (zmq:with-sockets ((receiver ctx :pull :connect "tcp://localhost:5557")
                         (sender ctx :push :connect "tcp://localhost:5558")
                         (controller ctx :sub :connect "tcp://localhost:5559"
                                     :subscribe ""))
        (zmq:with-message (msg)
          (zmq:with-poll-list (poll-list (recv receiver :pollin)
                                         (control controller :pollin))
            (loop
             (when (zmq:poll poll-list)
               (when (zmq:has-events-p recv)
                 (zmq:receive-message receiver msg :as 'zmq:string-message)
                 (sleep (/ (read-from-string (zmq:data msg)) 1000.0))
                 (zmq:send-message sender msg))
               (when (zmq:has-events-p control)
                 (return))))))))))

(let ((out *standard-output*))
  (defun tasksink2 ()
    (zmq:with-context (ctx)
      (zmq:with-sockets ((receiver ctx :pull :bind "tcp://*:5558")
                         (controller ctx :pub :bind "tcp://*:5559"))
        (zmq:with-message (msg)
          (zmq:receive-message receiver msg)
          (loop
           :for task-number :below 100
           :with start-time = (get-internal-real-time)
           :do
           (zmq:receive-message receiver msg)
           (if (zerop (mod task-number 10))
               (format out ":")
               (format out "."))
           :finally (format out "Total elapsed time: ~d msec~%"
                            (- (get-internal-real-time) start-time))))
        (zmq:send-message controller "KILL")))))


(defun run-parallel-pipeline (&optional (worker-count 1))
  (let ((workers (loop
                  :for count :below worker-count
                  :collect (bt:make-thread #'taskwork2
                                           :name (format nil "Worker-~D"
                                                         (1+ count)))))
        (sink (bt:make-thread #'tasksink2 :name "Sink")))
    (chapter-1::ventilator)
    (bt:join-thread sink)))

(defun wuproxy ()
  (zmq:with-context (ctx)
    (zmq:with-sockets ((frontend ctx :sub :connect "tcp://192.168.55.210:5556"
                                 :subscribe "")
                       (backend ctx :pub :bind "tcp://10.1.1.0:0100"))
      (zmq:with-message (msg)
        (loop
         (loop
          :do
          (zmq:receive-message frontend msg)
          (zmq:send-message backend msg :send-more (zmq:rcvmore frontend))))))))

(defun psenvpub ()
  (zmq:with-context (ctx)
    (zmq:with-socket (publisher ctx :pub :bind "tcp://*:5563")
      (loop
       (zmq:send-message publisher "A" :send-more t)
       (zmq:send-message publisher "We don't want to see this")
       (zmq:send-message publisher "B" :send-more t)
       (zmq:send-message publisher "We would like to see this")
       (sleep 1)))))

(defun psenvsub ()
  (zmq:with-context (ctx)
    (zmq:with-socket (subscriber ctx :sub
                                 :connect "tcp://localhost:5563"
                                 :subscribe "B")
      (loop
       (let ((address (zmq:receive-message subscriber :string))
             (contents (zmq:receive-message subscriber :string)))
         (format t "[~A] ~A~%" address contents))))))

(defun run-pspubsub ()
  (let ((pub-thread (bt:make-thread #'psenvpub :name "PS Publisher")))
    (unwind-protect
         (psenvsub)
      (bt:destroy-thread pub-thread))))

(defun durapub ()
  (zmq:with-context (ctx)
    (zmq:with-sockets ((sync ctx :pull :bind "tcp://*:5564")
                       (publisher ctx :pub :bind "tcp://*:5565"))
      (zmq:receive-message sync :string)
      (loop :for update-number :below 10 :do
        (zmq:send-message publisher (format nil "Update ~a" update-number))
        (sleep 1))
      (zmq:send-message publisher "END"))))

(defun durasub ()
  (zmq:with-context (ctx)
    (zmq:with-sockets ((subscriber ctx :sub
                                   :connect "tcp://localhost:5565"
                                   :subscribe ""
                                   :identity "Hello")
                       (sync ctx :push :connect "tcp://localhost:5564"))
      (zmq:send-message sync "")
      (loop
        :for count :below 3
        :as msg = (zmq:receive-message subscriber :string)
        :do (format t "~a~%" msg)
        :until (string= "END" msg)))))

