;;;; little-zmq.asd

(cl:eval-when (:load-toplevel :execute)
  (asdf:operate 'asdf:load-op 'cffi-grovel))

(asdf:defsystem #:little-zmq
  :serial t
  :depends-on (#:cffi
               #:alexandria)
  :components ((:module src
                :components ((:file "zmq-bindings-grovel")
                             (cffi-grovel:grovel-file "grovel.spec")
                             (:file "bindings")        
                             (:file "socket")
                             (:file "message")
                             (:file "poll")
                             (:file "little-zmq")))))

(asdf:defsystem #:little-zmq.devices
  :depends-on (#:little-zmq)
  :components ((:file "devices/standard-devices")))

(asdf:defsystem #:little-zmq.zguide-examples
  :depends-on (#:bordeaux-threads #:little-zmq #:cl-ppcre)
  :serial t
  :components ((:file "zguide/chapter-1")
               (:file "zguide/chapter-2")))

(asdf:defsystem #:little-zmq.tests
  :serial t
  :depends-on (#:bordeaux-threads
               #:little-zmq
               #:flexi-streams)
  :components ((:file "tests/util")
               (:file "tests/perf")))