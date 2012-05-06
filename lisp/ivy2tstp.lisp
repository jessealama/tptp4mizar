(in-package :cl-user)

(defgeneric ivy2tstp (ivy-thing)
  (:documentation "Transform IVY-THING into a TPTP derivation."))

(defmethod ivy2tstp :around ((ivy-thing pathname))
  (if (probe-file ivy-thing)
      (call-next-method)
      (error "There is no file at '~a'." (namestring ivy-thing))))

(defgeneric slurp (file-thing)
  (:documentation "The lines of FILE-THING as a single string."))

(defmethod slurp ((file-stream stream))
  (let* ((len (file-length file-stream))
	 (data (make-string len)))
    (read-sequence data file-stream)
    data))

(defmethod slurp :around ((file-path pathname))
  (if (probe-file file-path)
      (call-next-method)
      (error "There is no file at '~a'." (namestring file-path))))

(defmethod slurp ((file-path pathname))
  (with-open-file (file-stream file-path
			       :direction :input
			       :if-does-not-exist :error)
    (slurp file-stream)))

(defmethod ivy2tstp ((ivy-thing pathname))
  (ivy2tstp (slurp ivy-thing)))

(defun render-step-number (step-number)
  (format nil "~a" step-number))

(defgeneric render-term (ivy-term))

(defmethod render-term :around ((ivy-term list))
  (if (null ivy-term)
      (error "Cannot render the empty list as an Ivy term.")
      (call-next-method)))

(defmethod render-term ((ivy-term list))
  (let ((head (first ivy-term))
	(tail (rest ivy-term)))
    (if (null tail)
	(render-term head)
	(format nil "~(~a~)(~{~a~#[~:;, ~]~})" head (mapcar #'render-term tail)))))

(defmethod render-term ((ivy-term symbol))
  (let ((name (symbol-name ivy-term)))
    (if (eq (char name 0) #\V)
	(format nil "~@(~a~)" ivy-term)
	(format nil "~(~a~)" ivy-term))))

(defgeneric render-formula (ivy-formula))

(defmethod render-formula ((ivy-formula symbol))
  (format nil "~(~a~)" ivy-formula))

(defmethod render-formula :around ((ivy-formula list))
  (if (null ivy-formula)
      (error "Cannot render the empty list as an Ivy formula.")
      (call-next-method)))

(defmethod render-formula ((ivy-formula list))
  (let ((head (first ivy-formula)))
    (case head
      (or
       (format nil "(~a | ~a)"
	       (render-formula (second ivy-formula))
	       (render-formula (third ivy-formula))))
      (not
       (format nil "(~~ ~a)"
	       (render-formula (second ivy-formula))))
      (otherwise
       (format nil "~(~a~)(~{~a~#[~:;, ~]~})"
	       head
	       (mapcar #'render-term
		       (rest ivy-formula)))))))

(defun render-assignment (assignment)
  (destructuring-bind (variable . term)
      assignment
    (format nil "[~a,~a]" (render-term variable) (render-term term))))

(defun render-instantiation (instantiation)
  (format nil "[~{~a~#[~:;,~]~}]" (mapcar #'render-assignment instantiation)))

(defun render-disjunction-reference (reference)
  (format nil "[~{~a~#[~:;,~]~}]" reference))

(defun render-source (source)
  (let ((rule-name (first source))
	(tail (rest source)))
    (case rule-name
      (input
       "input")
      (instantiate
       (destructuring-bind (from instantiation)
	   tail
	 (format nil "inference(instantiate,[~a],[~a])"
		 (render-instantiation instantiation)
		 from)))
      (resolve
       (destructuring-bind (name-1 disjunct-1 name-2 disjunct-2)
	   tail
	 (format nil "inference(resolve,[~a,~a],[~a,~a])"
		 (render-disjunction-reference disjunct-1)
		 (render-disjunction-reference disjunct-2)
		 name-1
		 name-2)))
      (otherwise
       (error "Unknown rule of inference '~a'" rule-name)))))

(defun tptp-step (step-number formula source)
  (format nil "fof(~a,plain,~a,~a)." (render-step-number step-number)
	                             (render-formula formula)
				     (render-source source)))

(defun render-step (ivy-step)
  (destructuring-bind (step-number source formula whatever)
      ivy-step
    (declare (ignore whatever))
    (tptp-step step-number formula source)))

(defmethod ivy2tstp ((ivy-thing list))
  (with-output-to-string (s)
    (dolist (step ivy-thing)
      (format s "~a~%" (render-step step)))
    s))

(defmethod ivy2tstp ((ivy-thing string))
  (ivy2tstp (read-from-string ivy-thing)))
