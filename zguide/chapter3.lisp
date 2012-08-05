(in-package #:zguide-examples)

(defun gen-address (id node)
  (with-output-to-string (s)
    (format s "ipc://~S-~S.ipc" id node)))

(defun make-client (broker-name)
  (lambda ()
    (zmq:with-context (ctx)
      (zmq:with-sockets (((client ctx :req)
                          :connect (gen-address broker-name "localfe"))
                         ((monitor ctx :push)
                          :connect (gen-address broker-name "monitor")))
        (flet ((make-handler (task-id)
                 (lambda (skt revents)
                   (declare (ignore revents))
                   (let ((reply (zmq:recvmsg skt
                                             :message-type 'string-message)))
                     (assert (string= (zmq:data reply) task-id))
                     (zmq:sendmsg monitor reply)
                     (zmq:exit-poll)))))
          (loop
            :with task-lost = nil
            :until task-lost
            :do
            (sleep (random 5))  
            (dotimes (x (random 15))
              (let ((task-id (with-output-to-string (s)
                               (format s "~X" (random (expt 16 4))))))      
                (zmq:sendmsg client task-id)
                (zmq:with-polls (((client :pollin (make-handler task-id)))
                                 :timeout 10000)
                  ; body only entered if no event is found
                  (zmq:sendmsg monitor
                               (with-output-to-string (s)
                                 (format s "E: CLIENT EXIT - lost task ~a"
                                         task-id)))
                  (setf task-lost t))))))))))

(defun make-worker (broker-name)
  (lambda ()
    (zmq:with-context (ctx)
      (zmq:with-socket ((worker ctx :req)
                        :connect (gen-address broker-name "localbe"))
        (zmq:sendmsg worker (make-array 1 :element-type '(unsigned-byte 8)
                                          :initial-contents '(1)) )
        (loop
          (let ((msg (zmq:recvmsg worker)))
            (sleep (random 2))
            (zmq:sendmsg worker msg)))))))

(defun octet-data (msg)
  (zmq:data (change-class msg 'zmq:octet-message)))

(defun peering-3 (broker-name worker-count client-count &rest peers)
  (zmq:with-context (ctx)
    (zmq:with-sockets (((cloudfe ctx :router)
                        :identity broker-name
                        :bind (gen-address broker-name "cloud"))
                       ((statebe ctx :pub)                        
                        :bind (gen-address broker-name "state"))
                       ((cloudbe ctx :router)
                        :identity broker-name
                        :connect (loop :for peer :in peers
                                       :collect (gen-address peer "cloud")))
                       ((statefe ctx :sub)
                        :connect (loop :for peer :in peers
                                       :collect (gen-address peer "state")))
                       ((localfe ctx :router)
                        :bind (gen-address broker-name "localfe"))
                       ((localbe ctx :router)
                        :bind (gen-address broker-name "localbe"))
                       ((monitor ctx :router)
                        :bind (gen-address broker-name "monitor")))
      (let ((worker-threads (loop :for i :upto worker-count
                                  :collect
                                  (bt:make-thread (make-worker broker-name))))
            (client-threads (loop :for i :upto client-count
                                  :collect
                                  (bt:make-thread (make-client broker-name))))
            (timeout -1)
            (msg nil)
            (workers nil))
        (zmq:with-polls (((localbe
                           :pollin
                           (lambda (skt revents)
                             (declare (ignore revents))
                             (setf msg (zmq:recvall skt))
                             (setf workers (push (pop msg) workers))
                             (when (equalp #(1) (octet-data (second msg)))
                               (setf msg nil)))
                           (zmq:bypass-poll))
                          (cloudbe
                           :pollin
                           (lambda (skt revents)
                             (declare (ignore revents))
                             (setf msg (zmq:recvall skt))
                             (pop msg))))
                         :timeout timeout :loop t)
          
          (zmq:with-polls (((statefe
                             :pollin
                             (lambda (skt revents)))
                            (monitor
                             :pollin
                             (lambda (skt revents))))))
          (if (zerop (length workers)) -1 1000))))))