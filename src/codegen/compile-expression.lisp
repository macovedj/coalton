(defpackage #:coalton-impl/codegen/compile-expression
  (:use
   #:cl
   #:coalton-impl/util
   #:coalton-impl/codegen/ast
   #:coalton-impl/codegen/resolve-instance)
  (:import-from
   #:coalton-impl/codegen/typecheck-node
   #:typecheck-node)
  (:local-nicknames
   (#:tc #:coalton-impl/typechecker))
  (:export
   #:compile-toplevel
   #:compile-expression))

(in-package #:coalton-impl/codegen/compile-expression)

(defun compile-toplevel (name expr env)
  (declare (type symbol name)
           (type tc:typed-node expr)
           (type tc:environment env)
           (values node &optional))

  (let* ((inferred-type (tc:fresh-inst (tc:lookup-value-type env name)))

         (inferred-type-ty (tc:qualified-ty-type inferred-type))

         (inferred-type-preds (tc:qualified-ty-predicates inferred-type))

         (node-type (tc:qualified-ty-type (tc:fresh-inst (tc:typed-node-type expr))))

         (subs (tc:match inferred-type-ty node-type))

         (preds (tc:apply-substitution subs inferred-type-preds))

         (ctx (loop :for pred in preds
                    :collect (cons pred (gensym)))))

    (let ((node
            (cond
              ((tc:typed-node-abstraction-p expr)
               (let ((subnode (compile-expression (tc:typed-node-abstraction-subexpr expr) ctx env)))
                 (node-abstraction
                  (tc:make-function-type*
                   (append
                    (loop :for pred :in preds
                          :collect (pred-type pred env))
                    (loop :for (name . scheme) :in (tc:typed-node-abstraction-vars expr)
                          :collect (tc:qualified-ty-type (tc:ty-scheme-type scheme))))
                   (node-type subnode))
                  (append
                   (mapcar #'cdr ctx)
                   (mapcar #'car (tc:typed-node-abstraction-vars expr)))
                  subnode)))

              (ctx
               (let ((inner (compile-expression expr ctx env)))
                 (node-abstraction
                  (tc:make-function-type*
                   (loop :for pred :in preds
                         :collect (pred-type pred env))
                   (node-type inner))
                  (mapcar #'cdr ctx)
                  inner)))

              (t
               (compile-expression expr ctx env)))))

      (typecheck-node node env)
      node)))

(defun apply-dicts (expr ctx env)
  (declare (type tc:typed-node expr)
           (type pred-context ctx)
           (type tc:environment env)
           (values node))
  (let* ((qual-ty (tc:fresh-inst (tc:typed-node-type expr)))

         (dicts (mapcar
                 (lambda (pred)
                   (resolve-dict pred ctx env))
                 (tc:qualified-ty-predicates qual-ty)))

         (dict-types (mapcar #'node-type dicts))

         (var-type (tc:make-function-type*
                    dict-types
                    (tc:qualified-ty-type qual-ty)))

         (inner-node
           (typecase expr
             (tc:typed-node-variable (node-variable var-type (tc:typed-node-variable-name expr)))
             (t (compile-expression expr ctx env)))))

    (if (null dicts)
        inner-node
        (node-application
         (tc:qualified-ty-type qual-ty)
         inner-node
         dicts))))

(defgeneric compile-expression (expr ctx env)
  (:method ((expr tc:typed-node-literal) ctx env)
    (declare (type pred-context ctx)
             (type tc:environment env)
             (values node))
    (let ((qual-ty (tc:fresh-inst (tc:typed-node-type expr))))
      (assert (null (tc:qualified-ty-predicates qual-ty)))
      (node-literal
       (tc:qualified-ty-type qual-ty)
       (tc:typed-node-literal-value expr))))

  (:method ((expr tc:typed-node-variable) ctx env)
    (declare (type pred-context ctx)
             (type tc:environment env)
             (values node &optional))
    (apply-dicts expr ctx env))

  (:method ((expr tc:typed-node-application) ctx env)
    (declare (type pred-context ctx)
             (type tc:environment env)
             (values node))
    (let ((qual-ty (tc:fresh-inst (tc:typed-node-type expr))))
      (assert (null (tc:qualified-ty-predicates qual-ty)))
      (node-application
       (tc:qualified-ty-type qual-ty)
       (compile-expression (tc:typed-node-application-rator expr) ctx env)
       (mapcar
        (lambda (expr)
          (apply-dicts expr ctx env))
        (tc:typed-node-application-rands expr)))))

  (:method ((expr tc:typed-node-abstraction) ctx env)
    (declare (type pred-context ctx)
             (type tc:environment env)
             (values node))
    (let* ((qual-ty (tc:fresh-inst (tc:typed-node-type expr)))

           (preds (tc:qualified-ty-predicates qual-ty))

           (dict-var-names (loop :for pred :in preds
                                 :collect (gensym)))

           (dict-types (loop :for pred :in preds
                             :collect (pred-type pred env)))

           (ctx (append (loop :for pred :in preds
                              :for name :in dict-var-names
                              :collect (cons pred name))
                        ctx))

           (vars (append
                  dict-var-names
                  (loop :for (name . scheme) :in (tc:typed-node-abstraction-vars expr)
                        :collect
                        (let ((qual-ty (tc:fresh-inst scheme)))
                          (assert (null (tc:qualified-ty-predicates qual-ty)))
                          name)))))

      (assert (not (some #'tc:static-predicate-p preds)))
      (node-abstraction
       (tc:make-function-type* dict-types (tc:qualified-ty-type qual-ty))
       vars
       (compile-expression (tc:typed-node-abstraction-subexpr expr) ctx env))))

  (:method ((expr tc:typed-node-let) ctx env)
    (declare (type pred-context ctx)
             (type tc:environment env)
             (values node))
    (let ((qual-ty (tc:fresh-inst (tc:typed-node-type expr))))
      (assert (null (tc:qualified-ty-predicates qual-ty)))

      (node-let
       (tc:qualified-ty-type qual-ty)
       (loop :for (name . expr) :in (tc:typed-node-let-bindings expr)
             :collect (cons name (compile-expression expr ctx env)))
       (compile-expression (tc:typed-node-let-subexpr expr) ctx env))))

  (:method ((expr tc:typed-node-lisp) ctx env)
    (declare (type pred-context ctx)
             (type tc:environment env)
             (values node))
    (let ((qual-ty (tc:fresh-inst (tc:typed-node-type expr))))
      (assert (null (tc:qualified-ty-predicates qual-ty)))

      (node-lisp
       (tc:qualified-ty-type qual-ty)
       (tc:typed-node-lisp-variables expr)
       (tc:typed-node-lisp-form expr))))

  (:method ((expr tc:typed-match-branch) ctx env)
    (declare (type pred-context ctx)
             (type tc:environment env)
             (values match-branch))
    (match-branch
     (tc:typed-match-branch-pattern expr)
     (loop :for (name . scheme) :in (tc:typed-match-branch-bindings expr)
           :collect
           (let ((qual-ty (tc:fresh-inst scheme)))
             (assert (null (tc:qualified-ty-predicates qual-ty)))
             (cons name (tc:qualified-ty-type qual-ty))))
     (compile-expression (tc:typed-match-branch-subexpr expr) ctx env)))

  (:method ((expr tc:typed-node-match) ctx env)
    (declare (type pred-context ctx)
             (type tc:environment env)
             (values node-match))
    (let ((qual-ty (tc:fresh-inst (tc:typed-node-type expr))))
      (assert (null (tc:qualified-ty-predicates qual-ty)))
      (node-match
       (tc:qualified-ty-type qual-ty)
       (compile-expression (tc:typed-node-match-expr expr) ctx env)
       (mapcar
        (lambda (branch)
          (compile-expression branch ctx env))
        (tc:typed-node-match-branches expr)))))

  (:method ((expr tc:typed-node-seq) ctx env)
    (declare (type pred-context ctx)
             (type tc:environment env)
             (values node))
    (assert (not (null (tc:typed-node-seq-subnodes expr))))
    (let ((qual-ty (tc:fresh-inst (tc:typed-node-type expr))))
      (assert (null (tc:qualified-ty-predicates qual-ty)))
      (node-seq
       (tc:qualified-ty-type qual-ty)
       (mapcar
        (lambda (node)
          (compile-expression node ctx env))
        (tc:typed-node-seq-subnodes expr))))))

