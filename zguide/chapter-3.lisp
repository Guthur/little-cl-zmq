
(defpackage #:zguide.chapter-3
  (:nicknames #:chapter-3)
  (:use #:common-lisp)
  (:export))

(in-package zguide.chapter-3)

(defun dump (socket)
  (format t "~V,,,V<~>~%" 40 #\-)
  (zmq:with-message (msg)
    (loop
      :do
         (multiple-value-bind (msg length)
             (zmq:receive-message socket msg)
           (cond
             ((zerop length)
              (format t "[~a]~%" length))
             ((zerop (aref (zmq:data (message::as-octet-message msg)) 0))
              (format t "[~a] ~{~x~}~%" length
                      (coerce (zmq:data msg) 'list)))
             (t
              (format t "[~S] ~a~%"
                      length
                      (zmq:data (message::as-string-message msg))))))
      :while (zmq:rcvmore socket))))

(defun socket-identity ()
  (zmq:with-context (ctx)
    (zmq:with-sockets ((sink ctx :router :bind "inproc://example")
                       (anonymous ctx :req :connect "inproc://example")
                       (identified ctx :req
                                   :connect "inproc://example"
                                   :identity "Hello"))
      (zmq:send-message anonymous "ROUTER uses a generated UUID")
      (dump sink)
      (zmq:send-message identified "ROUTER uses REQ's socket identity")
      (dump sink))))


(let ((out *standard-output*))
  (defun worker-task-a ()
    (zmq:with-context (ctx)
      (zmq:with-socket (worker ctx :dealer
                               :connect "ipc://routing.ipc"
                               :identity "A")
        (loop
          :for count :from 0
          :until (string= "END" (zmq:receive-message worker :string))
          :finally (format out "A received: ~a~%" count))))))

(let ((out *standard-output*))
  (defun worker-task-b ()
    (zmq:with-context (ctx)
      (zmq:with-socket (worker ctx :dealer
                               :connect "ipc://routing.ipc"
                               :identity "B")
        (loop
          :for count :from 0
          :until (string= "END" (zmq:receive-message worker :string))
          :finally (format out "B received: ~a~%" count))))))

(defun rtdealer ()
  (zmq:with-context (ctx)
    (zmq:with-socket (client ctx :router :bind "ipc://routing.ipc")
      (let ((worker-a (bt:make-thread #'worker-task-a :name "Worker A"))
            (worker-b (bt:make-thread #'worker-task-b :name "Worker B")))
        (sleep 1)
        (loop
          :for task-number :below 10
          :do
             (if (> (random 3) 0)
                 (zmq:send-message client "A" :send-more t)
                 (zmq:send-message client "B" :send-more t))
             (zmq:send-message client "This is a workload"))
        (zmq:send-message client "A" :send-more t)
        (zmq:send-message client "END")
        (zmq:send-message client "B" :send-more t)
        (zmq:send-message client "END")))))

(defun generate-id ()
  (format nil "~x-~x" (random #x10000) (random #x10000)))

(let ((out *standard-output*))
  (defun worker-task ()
    (zmq:with-context (ctx)
      (zmq:with-socket (worker ctx :req
                               :connect "ipc://routing.ipc"
                               :identity (generate-id))
        (loop
          :for count :from 0
          :with msg
          :do
             (zmq:send-message worker "ready")
             (setf msg (zmq:receive-message worker :string))
             (sleep (random 1.0))
          :until (string= "END" msg)
          :finally (format out "Processed: ~d tasks~%" count))))))


(defparameter +number-of-workers+ 10)

(defun rtmama ()
  (zmq:with-context (ctx)
    (zmq:with-socket (client ctx :router :bind "ipc://routing.ipc")
      (let ((workers (loop
                       :for count :below +number-of-workers+
                       :collect (bt:make-thread #'worker-task
                                                :name (format nil "Worker-~d"
                                                              count)))))
        (loop
          :for task-number :below (* +number-of-workers+ 10)
          :as address = (zmq:receive-message client :string)
          :as empty = (zmq:receive-message client :string)
          :as ready = (zmq:receive-message client :string)
          :do
             (zmq:send-message client address :send-more t)
             (zmq:send-message client nil :send-more t)
             (zmq:send-message client "This is the workload"))
        (loop
          :for task-number :below +number-of-workers+
          :as address = (zmq:receive-message client :string)
          :as empty = (zmq:receive-message client :string)
          :as ready = (zmq:receive-message client :string)
          :do
             (zmq:send-message client address :send-more t)
             (zmq:send-message client nil :send-more t)
             (zmq:send-message client "END"))))))

(defun rtpapa ()
  (zmq:with-context (ctx)
    (zmq:with-sockets ((client ctx :router :bind "ipc://routing.ipc")
                       (worker ctx :rep
                               :connect "ipc://routing.ipc"
                               :identity "A"))
      (sleep 1)
      (zmq:send-message client "A" :send-more t)
      (zmq:send-message client "address 3" :send-more t)
      (zmq:send-message client "address 2" :send-more t)
      (zmq:send-message client "address 1" :send-more t)
      (zmq:send-message client nil :send-more t)
      (zmq:send-message client "This is the workload")
      (dump worker)
      (zmq:send-message worker "This is the reply")
      (dump client))))


(defparameter +number-clients+ 10)
(defparameter +number-workers+ 3)

(defun client-task ()
  (zmq:with-context (ctx)
    (zmq:with-socket (client ctx :req
                             :connect "ipc://frontend.ipc"
                             :identity (generate-id))
      (zmq:send-message client "HELLO")
      (format t "Client: ~S~%" (zmq:receive-message client :string)))))

(defun lru-worker-task ()
  (zmq:with-context (ctx)
    (zmq:with-socket (worker ctx :req
                             :connect "ipc://backend.ipc"
                             :identity (generate-id))
      (zmq:send-message worker "READY")
      (loop
        :as address = (zmq:receive-message worker :string)
        :as empty = (zmq:receive-message worker :octet)
        :do
           (assert (zerop (length empty)))
           (format t "Worker ~s~%" (zmq:receive-message worker :string))
           (zmq:send-message worker address :send-more t)
           (zmq:send-message worker nil :send-more t)
           (zmq:send-message worker "OK")))))

#++(defun lru-queue ()
  (zmq:with-context (ctx)
    (zmq:with-sockets ((frontend ctx :router :bind "ipc://frontend.ipc")
                       (backend ctx :router :bind "ipc://backend.ipc"))
      (let ((clients
              (loop
                :for client :below +number-clients+
                :collect (bt:make-thread #'client-task
                                         :name (format nil "Client-~s"
                                                       client))))
            (workers
              (loop
                :for worker :below +number-workers+
                :collect (bt:make-thread #'lru-worker-task
                                         :name (format nil "Worker-~s"
                                                       worker))))
            (available-workers (make-list 0)))
        (zmq:with-poll-list (poll-front-back (fb-front frontend :pollin)
                                             (fb-back backend :pollin))
          (zmq:with-poll-list (poll-back (b-back backend :pollin))
            (loop
             (zmq:poll (if available-workers
                           poll-front-back) ))))))))