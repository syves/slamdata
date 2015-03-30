module View (State(..), Action(..), spec) where

import Debug.Trace
import DOM (DOM())
import Control.Monad.Eff
import Signal.Channel (Chan())
import VirtualDOM.VTree (VTree())

import Utils (log)
import Component (Receiver(), Initial(), WidgetSpec())
import View.Shortcuts (div)
import Control.Timer (Timer())
import qualified View.Navbar as Navbar
import qualified View.Search as Search
import qualified View.List as List
import qualified View.Toolbar as Toolbar
import qualified View.Breadcrumb as Breadcrumb
import qualified Hash as Hash



-- | State is multiplication of children state
type State = {
  navbar :: Navbar.State,
  list :: List.State,
  toolbar :: Toolbar.State,
  breadcrumb :: Breadcrumb.Output
  }

initialState :: State
initialState = {
  navbar: Navbar.initialState,
  list: List.initialState,
  toolbar: Toolbar.initialState,
  breadcrumb: Breadcrumb.emptyOut
  }

-- | Action is sum of children actions
data Action = Init
            | ListAction List.Action
            | NavbarAction Navbar.Action
            | ToolbarAction Toolbar.Action
            | BreadcrumbAction Breadcrumb.Input

-- | Render function
view :: forall e. Receiver Action (chan::Chan,dom::DOM,timer::Timer|e) -> State ->
        Eff (chan::Chan, dom::DOM, timer::Timer|e) VTree
view send st = do
  -- Get children vtrees by sending substate and
  -- function projection to child receivers
  -- I think there is some cool word to name it, though,
  -- something like coprojection
  navbar <- Navbar.view (send <<< NavbarAction) st.navbar
  list <- List.view (send <<< ListAction) st.list
  toolbar <- Toolbar.view (send <<< ToolbarAction) st.toolbar
  breadcrumb <- Breadcrumb.render (send <<< BreadcrumbAction) st.breadcrumb
  -- Now as we have vtrees, we can add them to our template
  return $ div {} [
    navbar,
    div {"className": "container"} [
      breadcrumb,
      toolbar,
      list
      ]
    ]

-- | Almost all components that have children
-- | will use pattern matching to now if action
-- | have been sent by themself or their children
foldState :: forall e. Action -> State ->
             Eff (chan::Chan, dom::DOM, timer::Timer, trace::Trace|e) State
foldState action state =
  case action of
    -- Component action
    Init -> return initialState
    -- Children actions
    ListAction action ->
      state{list = _} <$> List.foldState action state.list
    NavbarAction action ->
      state{navbar = _} <$> Navbar.foldState action state.navbar
    ToolbarAction action -> do
      newState <- state{toolbar = _} <$> Toolbar.foldState action state.toolbar
      newList <- List.foldState (List.SortAction newState.toolbar.sort) state.list
      return newState{list = newList}
    BreadcrumbAction action ->
      state{breadcrumb = _} <$> Breadcrumb.run action state.breadcrumb

-- | Initial 
initial :: Initial Action State
initial = 
  {action: Init,
   state: initialState}
          
-- | Will be called after inserting
hookFn :: forall e. Receiver Action (chan::Chan, dom::DOM, trace::Trace|e) ->
                  Eff (chan::Chan, dom::DOM, trace::Trace|e) Unit
hookFn receiver = do
  Breadcrumb.hookFn (receiver <<< BreadcrumbAction)
  Navbar.hookFn (receiver <<< NavbarAction)
  List.hookFn (receiver <<< ListAction)
  Toolbar.hookFn (receiver <<< ToolbarAction)

-- | Spec 
spec :: forall e. WidgetSpec Action State (chan::Chan,
                                           dom::DOM,
                                           trace::Trace,
                                           timer::Timer|e)
spec = {
  render: view,
  initial: initial,
  updateState: foldState,
  hook: hookFn
  }