-- |
-- Module: Language.KURE.Combinators 
-- Copyright: (c) 2006-2008 Andy Gill
-- License: BSD3
--
-- Maintainer: Andy Gill <andygill@ku.edu>
-- Stability: unstable
-- Portability: ghc
--
-- This module contains various combinators that use 'Translate' and 'Rewrite'. The convension is that
-- 'Translate' based combinators end with @T@, and 'Rewrite' based combinators end with @R@. Of course,
-- because 'Rewrite' is a type synomim of 'Translate', the 'Rewrite' functions also operate with on 'Translate',
-- and the 'Translate' functions operate with 'Rewrite'. 

module Language.KURE.Combinators 
	(  -- * 'Translate' combinators
	  (<+)
	, (>->)
	, failT
	, readerT
	, getDecsT
	, mapDecsT
	, pureT
	, concatT
	, -- * 'Rewrite' combinators
	  (.+)
	, (!->)
	, tryR
	, changedR
	, acceptR
	, idR
	, failR
	) where 
	
import Language.KURE.RewriteMonad	
import Language.KURE.Translate	
import Language.KURE.Rewrite	
import Data.Monoid

-- infixl 3 <+, >->, .+, !->

-- Note: We use < for catching fail, . for catching id.

--------------------------------------------------------------------------------
-- The Translate combinators.

-- | like a catch, '<+' does the first translate , and if it fails, then does the second translate.	
(<+) :: (Monoid dec, Monad m) => Translate m dec a b -> Translate m dec a b -> Translate m dec a b
(<+) rr1 rr2 = translate $ \ e -> congruenceM $ apply rr1 e `catchM` (\ _ -> apply rr2 e)

-- | like a @;@ If the first translate succeeds, then do to the second translate after the first translate.
(>->) :: (Monoid dec, Monad m) => Translate m dec a b -> Translate m dec b c -> Translate m dec a c
(>->) rr1 rr2 = translate $ \ e -> congruenceM $ chainM (apply rr1 e) ( \ _i e2 -> apply rr2 e2)

-- | failing translation.
failT :: (Monad m, Monoid dec) => String -> Translate m dec a b
failT msg = translate $ \ e -> failM msg

-- | look at the argument for the translation before choosing which translation to perform. 
readerT :: (Monoid dec, Monad m) => (a -> Translate m dec a b) -> Translate m dec a b
readerT fn = translate $ \ expA -> congruenceM $ apply (fn expA) expA

-- | look at the @dec@ before choosing which translation to do.
getDecsT :: (Monad m, Monoid dec) => (dec -> Translate m dec a b) -> Translate m dec a b
getDecsT f = translate $ \ e -> congruenceM $
                                do dec <- getDecsM 
                                   apply (f dec) e

-- | change the @dec@'s for a scoped translation.
mapDecsT :: (Monoid dec,Monad m) => (dec -> dec) -> Translate m dec a r -> Translate m dec a r
mapDecsT f_env rr = translate $ \ e -> mapDecsM f_env (apply rr e)

-- | 'pureT' promotes a function into a unfailable, non-identity 'Translate'.
pureT :: (Monad m,Monoid dec) => (a -> b) -> Translate m dec a b
pureT f = translate $ \ a -> return (f a)

-- | 'concatT' composes a list of 'Translate' into a single 'Translate' which 'mconcat's its result.
concatT :: (Monad m,Monoid dec,Monoid r) => [Translate m dec a r] -> Translate m dec a r
concatT ts = translate $ \ e -> do
	rs <- sequence [ apply t e | t <- ts ]
	return (mconcat rs)
--------------------------------------------------------------------------------
-- The 'Rewrite' combinators.

-- | if the first rewrite is an identity, then do the second rewrite.
(.+) :: (Monoid dec, Monad m) => Rewrite m dec a -> Rewrite m dec a -> Rewrite m dec a
(.+) a b = a `wasId` (\ i -> if i then b else idR)

-- | if the first rewrite was /not/ an identity, then also do the second rewrite.
(!->) :: (Monoid dec, Monad m) => Rewrite m dec a -> Rewrite m dec a -> Rewrite m dec a 
(!->) a b = a `wasId` (\ i -> if i then idR else b)

-- | catch a failing 'Rewrite', making it into an identity.
tryR :: (Monoid dec, Monad m) => Rewrite m dec a -> Rewrite m dec a
tryR s = s <+ idR

-- | if this is an identity rewrite, make it fail. To succeed, something must have changed.
changedR :: (Monoid dec,Monad m) => Rewrite m dec a -> Rewrite m dec a
changedR rr = rr .+ failR "unchanged"

-- | repeat a rewrite until it fails, then return the result before the failure.
repeatR :: (Monoid dec, Monad m) => Rewrite m dec a -> Rewrite m dec a
repeatR s = tryR (s >-> repeatR s) 

-- | look at the argument to a rewrite, and choose to be either a failure of trivial success.
acceptR :: (Monoid dec, Monad m) => (a -> Bool) -> Rewrite m dec a
acceptR fn = translate $ \  expA -> congruenceM $
                                    if fn expA 
				    then return expA
				    else fail "accept failed"


-- | identity rewrite.
idR :: (Monad m, Monoid dec) => Rewrite m dec exp
idR = rewrite $ \ e -> congruenceM $ return e

-- | failing rewrite.
failR :: (Monad m, Monoid dec) => String -> Rewrite m dec a
failR = failT


--------------------------------------------------------------------------------
-- internal to this module.
wasId :: (Monoid dec, Monad m) => Rewrite m dec a -> (Bool -> Rewrite m dec a) -> Rewrite m dec a
wasId rr fn = translate $ \ e -> congruenceM $
	chainM (apply rr e)
	       (\ i e' -> apply (fn i) e')

