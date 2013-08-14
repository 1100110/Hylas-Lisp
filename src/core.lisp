(in-package :hylas)
(annot:enable-annot-syntax)

@document "Defines special forms and code language functions."

@doc "Please don't look at this code. Just don't. Please forgive me."
(defmacro extract (form (&rest bindings) &rest code)
  (let* ((str (make-string-output-stream))
         (bindings (loop for i from 0 to (1- (length bindings)) collecting
                     `((code (emit-code (nth ,i ,form) code))
                       (,(nth i bindings) (res code))
                       (,(read-from-string
                           (concatenate 'string
                             (symbol-name (nth i bindings)) "-type"))
                         (res-type code)))))
         (len (length bindings)))
    (format str "~{(let* ~A~}~{~S~}" bindings code)
    (dotimes (i len) (write-string ")" str))
    (read-from-string (get-output-stream-string str))))

(defmacro extract-list (form &rest code)
  `(let ((extracted-registers (list))
         (extracted-types (list)))
     (loop for cell in ,form do
       (let ((new-code (emit-code cell code)))
         (push (res new-code) extracted-registers)
         (push (res-type new-code) extracted-types)
         (setf code (copy-code new-code))))
     (setf extracted-registers (reverse extracted-registers))
     (setf extracted-types (reverse extracted-types))
     ,@code))

(defmacro with-new-scope (code-state &rest code)
  `(let ((code (copy-code ,code-state)))
     (push (make-instance '<scope>) (stack code))
     ,@code))

(defparameter *operators* (make-hash-table :test #'equal))
(defparameter *core* (make-hash-table :test #'equal))

(defmacro defbuiltin (table name &rest code)
  `(setf (gethash ,(format nil "~(~A~)" (symbol-name name)) ,table)
    #'(lambda (form code) ,@code)))

(defmacro defop (name &rest code)
  `(defbuiltin *operators* ,name ,@code))
(defmacro defcore (name &rest code)
  `(defbuiltin *core*,name ,@code))

;; Variables

(defop def
  (let ((sym (symbol-name (nth 0 form))))
    (extract (cdr form) (value)
      (multiple-value-bind (var pos) (lookup sym code)
        (if (eql pos (length (stack code)))
          (raise form "Symbol '~A' already defined in the present scope." sym)
          (progn
            (var sym (var value-type))
            (append-entry code
              (assign (emit "%~A" sym) (res code value-type)))))))))

(defop defglobal
  (let ((sym (symbol-name (nth 0 form))))
    (extract (cdr form) (value)
      (multiple-value-bind (var pos) (lookup sym code)
        (if (eql pos 0)
          (raise form "Symbol '~A' already defined in the global scope." sym)
          (progn
            (append-entry
              (append-toplevel code
                (emit "@~A = global ~A zeroinitializer" sym value-type))
              nil)))))))

(defop set
  (let ((sym (symbol-name (nth 0 form))))
    (extract (cdr form) (new-value)
      (let ((var (lookup sym code)))
        (if var
            (append-entry code
              (store new-value-type var new-value))
            (raise form "No symbol '~A' defined." sym))))))

;; Flow Control

(defop if
  (extract form (test true-branch false-branch)
    (if (not (booleanp test-type))
      (raise form "The type of the test expression to (if) must be i1 (boolean).")
      (if (match true-branch-type false-branch-type)
          ;match
          (append-entry code
            (emit "muh code"))
          ;no match
          (raise form "The types of the true and false branches must match")))))

(defop do
  (with-new-scope code
    (extract-list form
      code)))

;; Mathematics

(defmacro generic-twoarg-op (op)
  `(extract form (first second)
    (if (match first-type second-type)
      (append-entry code
        (assign (res code first-type)
          (emit "~A ~A ~A, ~A ~A" ,op first-type first second-type second)))
      (error "Types must match"))))

(defop add
  (generic-twoarg-op "add"))
(defop fadd
  (generic-twoarg-op "fadd"))
(defop sub
  (generic-twoarg-op "sub"))
(defop fsub
  (generic-twoarg-op "fsub"))
(defop mul
  (generic-twoarg-op "mul"))
(defop fmul
  (generic-twoarg-op "fmul"))
(defop udiv
  (generic-twoarg-op "udiv"))
(defop sdiv
  (generic-twoarg-op "sdiv"))
(defop fdiv
  (generic-twoarg-op "fdiv"))
(defop urem
  (generic-twoarg-op "urem"))
(defop srem
  (generic-twoarg-op "srem"))

;; Bitwise Operations

(defop shl
  (generic-twoarg-op "shl"))
(defop lshr
  (generic-twoarg-op "lshr"))
(defop ashr
  (generic-twoarg-op "ashr"))
(defop bit-and
  (generic-twoarg-op "and"))
(defop bit-or
  (generic-twoarg-op "or"))
(defop bit-xor
  (generic-twoarg-op "xor"))

(defop byte-swap)

(defop count-ones
  "Count the number of set bits in an integer.

  (count-ones b101010) => 3"
  (extract form (source)
    (append-toplevel
      (append-entry code
        (assign (res code source-type)
                (bitop "ctpop" source-type source)))
      (bitop-def "ctpop" source-type))))

(defop count-leading-ones
  (extract form (source)
    (append-toplevel
      (append-entry code
        (assign (res code source-type)
                (bitop "ctlz" source-type source)))
      (bitop-def "ctlz" source-type t))))

(defop count-trailing-ones
  (extract form (source)
    (append-toplevel
      (append-entry code
        (assign (res code source-type)
                (bitop "cttz" source-type source)))
      (bitop-def "cttz" source-type t))))

;; Conversion

(defmacro generic-conversion (op &rest validation)
  `(let ((to (parse-type (nth 0 form))))
      (extract form (source)
        ,@validation
        (append-entry code
          (assign (res code to)
                  (conv ,op source source-type to))))))

(defop truncate
  "Truncate an integer.

  (truncate 10 i8) => 10")
(defop sextend
  "Extend an integer preseving the sign.")
(defop extend
  "Zero-extend an integer.")

(defop ptr->int
  (generic-conversion "ptrtoint"
    (cond
      ((not (pointer? source-type))
        (bad-input-type form "ptr->int" "pointer" 1 source-type))
      ((not (integer? to))
        (bad-input-type form "ptr->int" "integer" 2 to)))))

(defop int->ptr
  (generic-conversion "ptrtoint"
    (cond
      ((not (pointer? source-type))
        (bad-input-type form "int->ptr" "integer" 1 source-type))
      ((not (integer? to))
        (bad-input-type form "int->ptr" "pointer" 2 to)))))

(defop bitcast
  "Converts any object to an integer of equal size.")
(defop coerce
  "Like (bitcast) but it don't give a fuck about size.")

;; Bitfield size

(defop size
  "Return the size of an object in bytes.

  (size 10) => 8 ;; i64
  (size 3.14) => 8 ;; double
  (size (i8 78)) => 1")

;; Data structures

(defop type
  (destructuring-bind (name def) form
    (append-entry (define-type name def code)
      (assign-res (int 1) (constant (int 1) "true")))))

(defop tuple
  "Create a tuple from its arguments.

  (tuple 1 2 3) => {1,1,1} with type {i64,i64,i64}
  (tuple \"/usr/bin/ls\" 755) => {\"/usr/bin/ls\",755} with type {i8*,i64}"
  (extract-list form
    (let ((tup-type (aggregate extracted-types)))
      (append-entry code
        (loop for i from 0 to (1- (length extracted-types)) collecting
          (let ((type (nth i extracted-types))
                (last-reg (res code)))
            (assign (res code tup-type)
                    (emit "insertvalue ~A ~A, ~A ~A, ~A" tup-type
                      (if (eql i 0) "undef" last-reg)
                      type (nth i extracted-registers) i))))))))

(defcore nth)
(defcore access)

;; Function definition and calling

(defop function
  (define-function form code))

(defop apply)

;; Vectors

#|(defop vector
  "Create a vector from its arguments.

  (vector 1 1 1) => <1,1,1> with type <3 x i64>
  (vector 1 3.14) => error
  (vector (vector 1 0 0)
          (vector 0 1 0)
          (vector 0 0 1)) => the identity matrix with type <9 x i64>")

(defop shuffle)|#

;; Memory

#|(defop allocate)
(defop store)
(defop load)|#

(defop create)
(defop reallocate)
(defop destroy)

(defop defmemman)

(defop address)
(defop fn)

;; FFI

(defop link
  "Link to a foreign library.

  (link \"GL\") => Links to the OpenGL library.

  (link
    (case os
      :windows \"SDL_mixer.dll\"
      :linux \"libSDL_mixer.so\")) => Links to the SDL Mixer library in a
                                      platform-independent way"
  (extract form (lib)
    (append-entry
      (append-toplevel code
        (emit "declare i8 @link(i8*)"))
      (assign (res code (int 8))
        (call "link" :ret (int 8)
                     :args (list (list lib lib-type)))))))

(defop foreign
  "Define a foreign function. The first argument is whether it's from a C or
C++ library. This information is used by Hylas to determine whether to mangle
the name of the function and how to do so.")

;; LLVM and Assembler

(defop asm)
(defop inline-asm)

(defop LLVM
  "Append a string of LLVM IR to the global scope."
  (let ((asm (nth 0 form)))
    (append-toplevel code
      asm)))

(defop inline-LLVM
  "Append a string of LLVM IR in the current context."
  (let ((asm (nth 0 form)))
    (append-entry code
      asm)))

(defparameter initial-code
  (make-instance '<code>
   :operators *operators*
   :core *core*))

;; Introspection

(defop declare)

(defop register)
(defop local)
(defop global)

(defop jit)
