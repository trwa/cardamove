use aiken/bytearray.{compare}
use aiken/dict.{Dict}
use cardamove/move/prelude.{Address}
use cardamove/move/state.{RunState}

// =====================================================================================================================
// Storage
// ---
// https://move-language.github.io/move/global-storage-operators.html
// =====================================================================================================================

pub type Storage<t> {
  internal: Dict<Address, t>,
}

fn has_key(storage: Storage<t>, address: Address) -> Bool {
  dict.has_key(storage.internal, address)
}

fn get(storage: Storage<t>, address: Address) -> Option<t> {
  dict.get(storage.internal, address)
}

fn insert(storage: Storage<t>, address: Address, value: t) -> Storage<t> {
  Storage { internal: dict.insert(storage.internal, address, value, compare) }
}

fn delete(storage: Storage<t>, address: Address) -> Storage<t> {
  Storage { internal: dict.delete(storage.internal, address) }
}

pub fn from_list(list: List<(Address, t)>) -> Storage<t> {
  let internal = dict.from_list(list, compare)
  Storage { internal }
}

// =====================================================================================================================
// MoveState Monad
// =====================================================================================================================

pub type MoveState<s, t> =
  RunState<s, Option<t>>

pub fn bind(m: MoveState<s, a>, k: fn(a) -> MoveState<s, b>) -> MoveState<s, b> {
  let s <- state.bind(state.get())
  let o <- state.bind(m)
  when o is {
    Some(x) -> k(x)
    None -> state.state(fn(_) { (None, s) })
  }
}

pub fn return(a: a) -> MoveState<s, a> {
  state.return(Some(a))
}

// =====================================================================================================================
// assert, move_to, move_from
// =====================================================================================================================

pub fn assert(condition: Bool) -> MoveState<g, Void> {
  if condition {
    state.return(Some(Void))
  } else {
    state.return(None)
  }
}

pub fn move_to(
  address: Address,
  value: t,
  get_storage: fn(g) -> Storage<t>,
  set_storage: fn(g, Storage<t>) -> g,
) -> MoveState<g, Void> {
  let s0: g <- state.bind(state.get())
  let storage = get_storage(s0)
  if has_key(storage, address) {
    state.return(None)
  } else {
    let s1 = set_storage(s0, insert(storage, address, value))
    let _ <- state.bind(state.put(s1))
    state.return(Some(Void))
  }
}

pub fn move_from(
  address: Address,
  get_storage: fn(g) -> Storage<t>,
  set_storage: fn(g, Storage<t>) -> g,
) -> MoveState<g, t> {
  let s0: g <- state.bind(state.get())
  let storage = get_storage(s0)
  when get(storage, address) is {
    None -> state.return(None)
    some -> {
      let s1 = set_storage(s0, delete(storage, address))
      let _ <- state.bind(state.put(s1))
      state.return(some)
    }
  }
}

// =====================================================================================================================
// Ref, borrow, assign
// =====================================================================================================================

pub opaque type Ref<t> {
  address: Address,
  value: t,
}

pub fn deref(a: Ref<t>) -> t {
  a.value
}

pub fn borrow_global(
  address: Address,
  get_storage: fn(g) -> Storage<t>,
  _set_storage: fn(g, Storage<t>) -> g,
) -> MoveState<g, Ref<t>> {
  let s0: g <- state.bind(state.get())
  let opt = get(get_storage(s0), address)
  when opt is {
    None -> state.return(None)
    Some(val) -> state.return(Some(Ref { address, value: val }))
  }
}

pub opaque type RefMut<t> {
  address: Address,
  value: t,
}

pub fn deref_mut(a: RefMut<t>) -> t {
  a.value
}

pub fn borrow_global_mut(
  address: Address,
  get_storage: fn(g) -> Storage<t>,
  _set_storage: fn(g, Storage<t>) -> g,
) -> MoveState<g, RefMut<t>> {
  let s0: g <- state.bind(state.get())
  let opt = get(get_storage(s0), address)
  when opt is {
    None -> state.return(None)
    Some(val) -> state.return(Some(RefMut { address, value: val }))
  }
}

pub fn assign_mut(
  what: RefMut<t>,
  value: t,
  get_storage: fn(g) -> Storage<t>,
  set_storage: fn(g, Storage<t>) -> g,
) -> MoveState<g, RefMut<t>> {
  let s0: g <- state.bind(state.get())
  let storage = get_storage(s0)
  let s1 = set_storage(s0, insert(storage, what.address, value))
  let _ <- state.bind(state.put(s1))
  return(RefMut { address: what.address, value })
}

pub fn exists(
  address: Address,
  get_storage: fn(g) -> Storage<t>,
) -> MoveState<g, Bool> {
  let st: g <- state.bind(state.get())
  let storage = get_storage(st)
  return(has_key(storage, address))
}
