(in-package #:coalton-user)

(coalton-toplevel
  ;;
  ;; Result
  ;;

  (define-type (Result :a :b)
    (Err :a)
    (Ok :b))

  (declare isOk ((Result :a :b) -> Boolean))
  (define (isOk x)
    (lisp Boolean
      (cl:etypecase x
	(Result/Ok True)
	(Result/Err False))))

  (declare isErr ((Result :a :b) -> Boolean))
  (define (isErr x)
    (lisp Boolean
      (cl:etypecase x
	(Result/Err True)
	(Result/Ok False))))

  (declare mapErr ((:a -> :b) -> (Result :a :c) -> (Result :b :c)))
  (define (mapErr f x)
    (match x
      ((Err x) (Err (f x)))
      ((Ok x) (Ok x))))

  ;;
  ;; Result instances
  ;;

  (define-instance ((Eq :a) (Eq :b) => (Eq (Result :a :b)))
    (define (== a b)
      (match (Tuple a b)
	((Tuple (Ok a) (Ok b)) (== a b))
	((Tuple (Err a) (Err b)) (== a b))
	(_ False)))
    (define (/= a b) (not (== a b))))

  (define-instance ((Ord :a) (Ord :b) => (Ord (Result :a :b)))
    (define (<=> a b)
      (match (Tuple a b)
	((Tuple (Ok a) (Ok b)) (<=> a b))
	((Tuple (Err a) (Err b)) (<=> a b))
	((Tuple (Err _) (Ok _)) LT)
	((Tuple (Ok _) (Err _)) GT))))

  (define-instance (Semigroup :b => (Semigroup (Result :a :b)))
    (define (<> a b)
      (match (Tuple a b)
	((Tuple (Ok x) (Ok y))
	 (Ok (<> x y)))
	((Tuple (Err _) _) a)
	(_ b))))

  (define-instance (Monoid :b => (Monoid (Result :a :b)))
    (define mempty (Ok mempty)))

  (define-instance (Functor (Result :a))
    (define (map f x)
      (match x
	((Ok x) (Ok (f x)))
	((Err e) (Err e)))))

  (define-instance (Applicative (Result :a))
    (define (pure x) (Ok x))
    (define (liftA2 f a b)
      (match (Tuple a b)
	((Tuple (Ok a) (Ok b))
	 (Ok (f a b)))
	((Tuple (Err e) _) (Err e))
	((Tuple _ (Err e)) (Err e)))))

  (define-instance (Monad (Result :a))
    (define (>>= m f)
      (match m
	((Ok x) (f x))
	((Err e) (Err e))))
    (define (>> ma mb)
      (>>= ma (fn (_) mb)))))