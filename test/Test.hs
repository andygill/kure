{-# LANGUAGE TypeFamilies, MultiParamTypeClasses #-}

module Main where

import Language.KURE
import Language.KURE.Term as T

import Data.Monoid
import Control.Monad
import Data.List
import Debug.Trace


import Exp
import Id

type R e = Rewrite Id () e
type T e1 e2 = Translate Id () e1 e2

main = do
	let es1 = [e1,e2,e3,e4,e5,e6,e7,e8,e9,e10,e11]
	sequence_ [ print e | e <- es1]

	let frees :: Exp -> Id [Name]
	    frees exp = do Right (fs,b) <- runTranslate freeExpT () exp
			   return $ nub fs
	let e_frees = map (runId . frees) es1
	sequence_ [ print e | e <- e_frees]
        
        sequence [ print (e,function (substExp v ed) e)  | v <- ["x","y","z"], ed <- es1, e <- es1 ]

        sequence  [ print (runId $ runTranslate betaRedR () e) | e <- es1 ]
        let fn = extractR (topdownR (repeatR betaRedR))
        sequence  [ print (runId $ runTranslate fn () e) | e <- es1 ]
        
        
------------------------------------------------------------------------
--
-- First the guards
--

appG :: R Exp
appG = acceptR $ \ e -> case e of { App {} -> True ; _ -> False }

lamG :: R Exp
lamG = acceptR $ \ e -> case e of { Lam {} -> True ; _ -> False }

varG :: R Exp
varG = acceptR $ \ e -> case e of { Var {} -> True; _ -> False }

------------------------------------------------------------------------
--
-- Then the rewrites and Universals
--


appR :: R Exp 
                              -> R Exp
                              -> R Exp
appR rr1 rr2 = appG >-> rewrite (\ (App e1 e2) -> 
                                transparently $ 
                                liftM2 App (apply rr1 e1) 
                                           (apply rr2 e2)) 

lamR :: R Exp 
                              -> R Exp
lamR rr = lamG >-> rewrite (\ (Lam n e) -> 
                                transparently $ do
                                e' <- apply rr e
                                return $ Lam n e')
                                           
varR :: R Exp
varR = varG

appU :: (Monoid r) => 
                                 T Exp r
                              -> T Exp r
                              -> T Exp r
appU rr1 rr2 = appG >-> translate (\ (App e1 e2) -> 
                                liftM2 mappend (apply rr1 e1) 
                                               (apply rr2 e2)) 

lamU :: (Monoid r) => T Exp r
                              -> T Exp r
lamU rr = lamG >-> translate (\ (Lam n e) -> do
                                e' <- apply rr e
                                return $ e')
                                           
varU :: (Monoid r) => T Exp r
varU = varG >-> translate (\ _ -> return $ mempty)


------------------------------------------------------------------------
--
-- Finally, the pattern matches
--

appP ::(Exp -> Exp -> T Exp r)
                              -> T Exp r
appP f = appG >-> readerT (\ (App e1 e2) -> f e1 e2) 

lamP ::  (Name -> Exp -> T Exp r)
                              -> T Exp r
lamP f = lamG >-> readerT (\ (Lam n e) -> f n e)

varP :: (Name -> T Exp r)
                              -> T Exp r
varP f = varG >-> readerT (\ (Var n) -> f n)

------------------------------------------------------------------------

instance Walker Id () Exp where
   allR rr = appR rr rr <+ lamR rr <+ varR
   crushU rr = appU rr rr <+ lamU rr <+ varU

function :: Translate Id () a b -> a -> b
function f a = runId $ do 
        Right (b,_) <- runTranslate f () a
	return $ b

------------------------------------------------------------------------

freeExpT :: T Exp [Name]
freeExpT = lambda <+ var <+ crushU freeExpT
  where
          var    = varG >-> translate (\ (Var v) -> return [v])
          lambda = lamG >-> translate (\ (Lam n e) -> do
                frees <- apply freeExpT e
                return (nub frees \\ [n]))
                
freeExp :: Exp -> [Name]
freeExp = function freeExpT

newName :: Name -> [Name] -> Name
newName suggest frees = 
        head [ nm | nm <- suggest : suggests
             , nm `notElem` frees
             ]
   where suggests = [ suggest ++ "_" ++ show n | n <- [1..]]

-- Only works for lambdas, fails for all others
shallowAlpha :: [Name] -> R Exp
shallowAlpha frees' = lamG >-> 
                        rewrite (\ (Lam n e) -> do
                frees <- apply freeExpT e
                let n' = newName n (frees ++ frees')
                e' <- apply (substExp n (Var n')) e
                return $ Lam n' e') 

substExp :: Name -> Exp -> R Exp
substExp v s = rule1 <+ rule2 <+ rule3 <+ rule4 <+ rule5 <+ rule6
 where
        -- From Lambda Calc Textbook, the 6 rules.
        rule1 = varP $ \ n -> n == v ? constT s
        rule2 = varP $ \ n -> n /= v ? idR
        rule3 = lamP $ \ n e -> n == v ? idR
        rule4 = lamP $ \ n e -> (n `notElem` freeExp s || v `notElem` freeExp e) 
                                ? allR (substExp v s)
        rule5 = lamP $ \ n e -> (n `elem` freeExp s && v `elem` freeExp e)
                                ? (shallowAlpha (freeExp s) >-> substExp v s)
        rule6 = appG >-> allR (substExp v s)

              
-------------

betaRedR :: R Exp
betaRedR = rewrite $ \ e ->
   case e of
     (App (Lam v e1) e2) -> apply (substExp v e2) e1
     _ -> fail "betaRed"

debugR :: (Show e) => String -> R e      
debugR msg = translate $ \ e -> transparently $ trace (msg ++ " : " ++ show e) (return e)

