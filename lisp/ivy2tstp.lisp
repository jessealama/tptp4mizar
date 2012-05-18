(in-package :cl-user)

(set-syntax-from-char #\| #\a) ;; in case we get disjunctions like (|a b)

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

(defun comma-separated-list (list)
  (format nil "~{~a~#[~:;,~]~}" list))

(defmethod render-term ((ivy-term list))
  (let ((head (first ivy-term))
	(tail (rest ivy-term)))
    (if (null tail)
	(render-term head)
	(format nil "~(~a~)(~a)" head
		                 (comma-separated-list (mapcar #'render-term tail))))))

(defmethod render-term ((ivy-term symbol))
  (let ((name (symbol-name ivy-term)))
    (if (eq (char name 0) #\V)
	(format nil "~@(~a~)" ivy-term)
	(format nil "~(~a~)" ivy-term))))

(defgeneric render-formula (ivy-formula))

(defun lowercase (str)
  (format nil "~(~a~)" str))

(defmethod render-formula ((ivy-formula symbol))
  (let ((name (symbol-name ivy-formula)))
    (if (string= (lowercase name) "false")
	"$false"
	(format nil "~(~a~)" ivy-formula))))

(defmethod render-formula :around ((ivy-formula list))
  (if (null ivy-formula)
      (error "Cannot render the empty list as an Ivy formula.")
      (call-next-method)))

(defmethod render-formula ((ivy-formula list))
  (let ((head (first ivy-formula))
	(tail (rest ivy-formula)))
    (case head
      (or
       (format nil "(~a | ~a)"
	       (render-formula (second ivy-formula))
	       (render-formula (third ivy-formula))))
      (not
       (format nil "(~~ ~a)"
	       (render-formula (second ivy-formula))))
      (=
       (format nil "(~a = ~a)"
	       (render-term (second ivy-formula))
	       (render-term (third ivy-formula))))
      ($quantified
       (destructuring-bind ((quantifier) variable matrix)
	   tail
	 (case quantifier
	   (all
	    (format nil "(! [~a] : ~a)"
		    (render-term variable) (render-formula matrix)))
	   (exists
	    (format nil "(? [~a] : ~a)"
		    (render-term variable) (render-formula matrix)))
	   (otherwise
	    (error "Unknown quantifier '~a'." quantifier)))))
      (\|
       (format nil "(~a | ~a)"
	       (render-formula (second ivy-formula))
	       (render-formula (third ivy-formula))))
      (-
       (format nil "(~~ ~a)"
	       (render-formula (second ivy-formula))))
      (otherwise
       (format nil "~(~a~)(~a)"
	       head
	       (comma-separated-list (mapcar #'render-term
					     (rest ivy-formula))))))))

(defun render-assignment (assignment)
  (destructuring-bind (variable . term)
      assignment
    (format nil "[~a,~a]" (render-term variable) (render-term term))))

(defun render-instantiation (instantiation)
  (comma-separated-list (mapcar #'render-assignment
				instantiation)))

(defun render-disjunction-reference (reference)
  (format nil "[~a]" (comma-separated-list reference)))

(defun render-instantiate-step (step)
  (destructuring-bind (from instantiation)
      step
    (format nil "inference(instantiate,[~a],[~a])"
	    (render-instantiation instantiation)
	    from)))

(defun render-resolve-step (step)
  (destructuring-bind (name-1 disjunct-1 name-2 disjunct-2)
      step
    (format nil "inference(resolve,[~a,~a],[~a,~a])"
	    (render-disjunction-reference disjunct-1)
	    (render-disjunction-reference disjunct-2)
	    name-1
	    name-2)))

(defun render-flip-step (step)
  (destructuring-bind (formula-name disjunct-address)
      step
    (format nil "inference(flip,[~a],[~a])"
	    (comma-separated-list disjunct-address)
	    formula-name)))

(defun render-paramod-step (step)
  (destructuring-bind (name-1 disjunct-1 name-2 disjunct-2)
      step
    (format nil "inference(paramod,[~a,~a],[~a,~a])"
	    (render-disjunction-reference disjunct-1)
	    (render-disjunction-reference disjunct-2)
	    name-1
	    name-2)))

(defun render-propositional-step (step)
  (destructuring-bind (formula-name)
      step
    (format nil "inference(propositional,[],[~a])" formula-name)))

(defun render-clausify-step (step)
  (destructuring-bind (formula-name)
      step
    (format nil "inference(clausify,[],[~a])" formula-name)))

(defun render-source (source)
  (let ((rule-name (first source))
	(tail (rest source)))
    (case rule-name
      (input
       "input")
      (instantiate
       (render-instantiate-step tail))
      (resolve
       (render-resolve-step tail))
      (flip
       (render-flip-step tail))
      (paramod
       (render-paramod-step tail))
      (propositional
       (render-propositional-step tail))
      (clausify
       (render-clausify-step tail))
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

(defun print-ivy2tstp (ivy-thing)
  (format t "~a" (ivy2tstp ivy-thing)))
