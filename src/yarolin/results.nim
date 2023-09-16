when defined(nimHasEffectsOf):
  {.experimental: "strictEffects".}
else:
  {.pragma: effectsOf.}

when (NimMajor, NimMinor) >= (1, 1):
  type SomePointer = ref | ptr | pointer | proc
else:
  type SomePointer = ref | ptr | pointer

import macros, strformat

type
  Result*[V, E] = object ## The result container type. Applies optimization \
    ## when ``V`` or ``E`` are pointer types.
    when V isnot SomePointer and E isnot SomePointer:
      successful: bool
    val: V
    err: E

  UnpackValDefect* = object of Defect ## Defect thrown during the unpacking of\
    ## the value from a failure result.
  UnpackErrDefect* = object of Defect ## Defect thrown during the unpacking of\
    ## the error from a success result.

# TODO: Add more examples.

func `$`*[V, E](res: Result[V, E]): string =
  if res.successful():
    fmt"Success({res.unsafeGetVal()[]})"
  else:
    fmt"Failure({res.unsafeGetErr()[]})"

template `!`*[E, V](err: typedesc[E], val: typedesc[V]): untyped =
  ## Creates a result type ``Result[V, E]`` where ``E!V``.
  ##
  ## .. code-block:: nim
  ##
  ##    int!void # Same as `Result[void, int]`
  ##    string!float # Same as `Result[float, string]`
  Result[V, E]

func success*[V: void; E](): Result[V, E] {.inline.} =
  ## Creates a success result with a missing value.
  when V isnot SomePointer and E isnot SomePointer: # we can't use ``nil`` for\
                                                    # any of the fields to\
                                                    # indicate the state, so we
                                                    # set the boolean flag
    result.successful = true
  else:
    result.err = nil
proc success*[V: not void; E](val: sink V): Result[V, E] {.inline.} =
  ## Creates a success result with ``val`` as value.
  result.val = val
  when V isnot SomePointer and E isnot SomePointer:
    result.successful = true
  else:
    result.err = nil
proc failure*[V; E: void](): Result[V, E] {.inline.} =
  ## Creates a failure result with a missing error.
  when E isnot SomePointer and V isnot SomePointer:
    result.successful = false
  else:
    result.err = nil
func failure*[V; E: not void](err: sink E): Result[V, E] {.inline.} =
  ## Creates a failure result with ``err`` as error.
  result.err = err
  when E isnot SomePointer and V isnot SomePointer:
    result.successful = false
  else:
    result.err = nil

func default*[V, E](resType: typedesc[Result[V, E]]): Result[V, E] =
  failure[V, E](default(V))

proc successful*[V, E](res: Result[V, E]): bool {.inline.} =
  ## Checks whether a given result ``res`` is a success result or not.
  ##
  ## .. code-block:: nim
  ##
  ##    success[int, int](10).successful() # true
  ##    failure[int, int](10).successful() # false
  when V is SomePointer:
    result = not isNil(res.val)
  elif E is SomePointer:
    result = isNil(res.err)
  else:
    result = res.successful
proc unsuccessful*[V, E](res: Result[V, E]): bool {.inline.} =
  ## Checks whether a given result ``res`` is a failure result or not.
  not successful(res)

proc unsafeGetVal*[V, E](res: Result[V, E]): ptr V {.inline.} =
  ## Gets a pointer to the value of the result ``res`` regardless of its state.
  addr res.val
proc unsafeGetErr*[V, E](res: Result[V, E]): ptr E {.inline.} =
  ## Gets a pointer to the error of the result ``res`` regardless of its state.
  addr res.err

proc getVal*[V, E](res: sink Result[V, E]): V
                  {.inline, raises: UnpackValDefect.} =
  ## Unpacks and returns the value if the result ``res`` is successful, raises
  ## ``UnpackValDefect`` otherwise.
  ##
  ## .. code-block:: nim
  ##
  ##    success[int, int](44).getVal() # 44
  ##    failure[int, int](45).getVal() # raises `UnpackValDefect`
  if not res.successful():
    raise newException(
      UnpackValDefect,
      "Tried to get the value of an failure Result")
  when V isnot void:
    result = res.val
proc getErr*[V, E](res: sink Result[V, E]): E
                  {.inline, raises: UnpackErrDefect.} =
  ## Unpacks the error if the result ``res`` is unsuccessful, raises
  ## ``UnpackErrDefect`` otherwise.
  ##
  ## .. code-block:: nim
  ##
  ##    success[int, int](44).getErr() # 44
  ##    failure[int, int](45).getErr() # raises `UnpackErrDefect`
  if res.successful():
    raise newException(
      UnpackErrDefect,
      "Tried to get the error of a success Result")
  when E isnot void:
    result = res.err

template `!+`*[V, E](resultType: typedesc[Result[V, E]], val: sink V): untyped =
  ## Given a result type ``R := Result[V, E]`` and a value ``val: V``,
  ## creates a success result of type ``R`` with ``val`` as value.
  ##
  ## .. code-block:: nim
  ##
  ##    type R = Result[int, int]
  ##    let res = R !+ 12 # same as success[R.V, R.E](12)
  ##    # or
  ##    let res = int!int !+ 12
  success[V, E](val)
template `!-`*[V, E](resultType: typedesc[Result[V, E]], err: sink E): untyped =
  ## Given a result type ``R := Result[V, E]`` and a value ``err: E``,
  ## creates a failure result of type ``R`` with ``err`` as error.
  ##
  ## .. code-block:: nim
  ##
  ##    type R = Result[int, int]
  ##    let res = R !- 43 # same as failure[R.V, R.E](43)
  ##    # or
  ##    let res = int!int !- 43 # same as failure[R.V, R.E](43)
  failure[V, E](err)

template `=!+`*[V, E](res: var Result[V, E], val: sink V): untyped =
  ## Given a variable ``res: var R`` where ``R := Result[V, E]`` and a value
  ## ``val: V``, assigns ``res`` a success result of type ``R`` with ``val``
  ## as value.
  ##
  ## .. code-block:: nim
  ##
  ##    proc foo(stuff: varargs[string]): string!int =
  ##      # .. stuff?
  ##      if smth:
  ##        result =!+ 943
  ##        return
  ##      # .. other stuff
  res = success[V, E](val)
template `=!-`*[V, E](res: var Result[V, E], err: sink E): untyped =
  ## Given a variable ``res: var R`` where ``R := Result[V, E]`` and a value
  ## ``err: E``, assigns ``res`` a failure result of type ``R`` with ``err``
  ## as error.
  ##
  ## .. code-block:: nim
  ##
  ##    proc foo(stuff: varargs[string]): string!int =
  ##      # .. stuff?
  ##      if not smth:
  ##        result =!- "smth is false"
  ##        return
  ##      # .. other stuff
  res = failure[V, E](err)

template returnVal*: untyped =
  return success[result.V, result.E]()
template returnVal*(val: untyped): untyped =
  return success[result.V, result.E](val)

template returnErr*: untyped =
  return failure[result.V, result.E]()
template returnErr*(err: untyped): untyped =
  return failure[result.V, result.E](err)

macro `or`*[V, E](res: sink Result[V, E], body: untyped): untyped =
  ## Given a value ``res: Result[V, E]``  and a tree (aka. whatever) ``body``,
  ## unpacks the value of ``res`` of it is successful, otherwise executes
  ## ``body``.
  ##
  ## .. code-block:: nim
  ##
  ##    discard success[int, int](1232) or (block:
  ##      echo "Never gets executed"
  ##      0)
  ##    discard failure[int, int](0xdeadbabe) or (block:
  ##      echo "This one does though"
  ##      0) # we need the `0` so that the compiler doesn't complain about
  ##         # incompatible types.
  runnableExamples:
    proc foo(fail: bool): int!int =
      if fail:
        result =!- 40
      else:
        result =!+ 48
    proc bar(fail: bool): int!int =
      let value = foo(fail) or (block: return int!int !- 1; 0)
      result =!+ value
    doAssert bar(false).getVal() == 48
    doAssert bar(true).getErr() == 1
  let resSym = genSym(ident = "res")
  quote do:
    let `resSym` = `res`
    if `resSym`.successful():
      `resSym`.unsafeGetVal()[]
    else:
      `body`

# TODO: Doc comments
macro `try`*[V, E](res: Result[V, E]): untyped =
  let resSym = genSym(ident = "res")
  quote do:
    let `resSym` = `res`
    if `resSym`.successful():
      `resSym`.unsafeGetVal()[]
    else:
      result =!- `resSym`.unsafeGetErr()[]
      return

func throw*[V, E, X](res: sink Result[V, E], errorType: typedesc[X]): V =
  if not res.successful():
    raise newException(X, $(res.unsafeGetErr()[]))
  when V isnot void:
    result = res.val

func throw*[V, E](res: sink Result[V, E]): V =
  when V isnot void:
    result = res.throw(CatchableError)

macro with*[V, E](res: Result[V, E], body: untyped): untyped =
  let resSym = genSym(ident = "res")
  body.expectLen 1, 2
  result =
    nnkStmtList.newTree(
      nnkLetSection.newTree(
        nnkIdentDefs.newTree(
          resSym,
          newEmptyNode(),
          res)))
  var
    onFailure: NimNode = nil
    onSuccess: NimNode = nil
  for `case` in body:
    `case`.expectKind nnkCall
    `case`.expectLen 3
    `case`[0].expectKind nnkIdent
    `case`[1].expectKind { nnkIdent, nnkVarTy }
    var branch =
      if `case`[0].strVal == "successful":
        onSuccess = nnkStmtList.newNimNode()
        onSuccess
      elif `case`[0].strVal == "failure":
        onFailure = nnkStmtList.newNimNode()
        onFailure
      else:
        error(
          fmt"Expected 'successful' or 'failure', found {`case`[0].strVal}",
          `case`[0])
        break
    let
      (isMutable, varName) =
        if `case`[1].kind == nnkIdent: (false, `case`[1])
        else: (true, `case`[1][0])
      varDecl = 
        if varName.strVal == "_":
          newEmptyNode()
        else:
          newTree(
            if isMutable: nnkVarSection else: nnkLetSection,
            nnkIdentDefs.newTree(
              varName,
              newEmptyNode(),
              nnkBracketExpr.newTree(
                nnkCall.newTree(
                  if branch == onFailure: bindSym"unsafeGetErr"
                  else: bindSym"unsafeGetVal",
                  resSym))))
    branch.add(nnkStmtList.newTree(varDecl, `case`[2]))
  var
    ifStmt = nnkIfStmt.newNimNode()
    elifBrach = nnkElifBranch.newNimNode()
    elseBranch: NimNode = nil
  var
    cond = nnkCall.newTree(bindSym"successful", resSym)
    actions = onSuccess
  if isNil(onSuccess):
    cond = nnkPrefix.newTree(bindSym"not", cond)
    actions = onFailure
  elif body.len == 2:
    elseBranch = nnkElse.newTree(onFailure)
  elifBrach.add(cond, actions)
  ifStmt.add(elifBrach)
  if not isNil(elseBranch):
    ifStmt.add(elseBranch)
  result.add(ifStmt)

proc successfulAnd*[V, E](res: Result[V, E], fn: proc(val: V): bool): bool
                         {.effectsOf: fn.} =
  result = false
  if res.successful():
    result = fn(res.val)
proc unsuccessfulAnd*[V, E](res: Result[V, E], fn: proc(err: E): bool): bool
                           {.effectsOf: fn.} =
  result = false
  if res.unsuccessful():
    result = fn(res.err)

macro successfulAndIt*[V, E](res: Result[V, E], body: untyped): untyped =
  let resSym = genSym(ident = "res")
  quote do:
    let `resSym` = `res`
    if `resSym`.successful():
      let it {.inject.} = `resSym`.unsafeGetVal()[]
      `body`
    else:
      false
macro unsuccessfulAndIt*[V, E](res: Result[V, E], body: untyped): untyped =
  let resSym = genSym(ident = "res")
  quote do:
    let `resSym` = `res`
    if `resSym`.unsuccessful():
      let it {.inject.} = `resSym`.unsafeGetErr()[]
      `body`
    else:
      false

proc mapVal*[V, E, U](res: sink Result[V, E],
                      fn: proc(val: V): U): Result[U, E] {.effectsOf: fn.} =
  if res.successful():
    return success[U, E](fn(res.val))
  return failure[U, E](res.err)
proc mapValOr*[V, E, U](res: sink Result[V, E],  
                        default: U,
                        fn: proc(val: V): U): U {.effectsOf: fn.} =
  if res.successful():
    return fn(res.val)
  return default
proc mapValOrElse*[V, E, U](res: sink Result[V, E],
                            defaultFn: proc(err: E): U,
                            fn: proc(val: V): U): U
                           {.effectsOf: [fn, defaultFn].} =
  if res.successful():
    return fn(res.val)
  return defaultFn(res.err)

macro mapValIt*[V, E](res: sink Result[V, E], body: untyped): untyped =
  let
    resSym = genSym(ident = "res")
    uSym = genSym(nskType, ident = "U")
  quote do:
    type
      `uSym` = typeof(block:
        var it {.inject, noinit.}: typeof(`res`.getVal())
        `body`)
    let `resSym` = `res`
    if `resSym`.successful():
      success[`uSym`, `resSym`.E](block:
        let it {.inject.} = `resSym`.unsafeGetVal()[]
        `body`)
    else:
      failure[`uSym`, `resSym`.E](`resSym`.unsafeGetErr()[])
macro mapValOrIt*[V, E, U](res: sink Result[V, E],
                           default: U,
                           body: untyped): untyped =
  let resSym = genSym(ident = "res")
  quote do:
    let `resSym` = `res`
    if `resSym`.successful():
      let it {.inject.} = `resSym`.unsafeGetVal()[]
      `body`
    else:
      `default`
macro mapValOrElseIt*[V, E](res: sink Result[V, E];
                            errBody, body: untyped): untyped =
  let resSym = genSym(ident = "res")
  quote do:
    let `resSym` = `res`
    if `resSym`.successful():
      let it {.inject.} = `resSym`.unsafeGetVal()[]
      `body`
    else:
      let it {.inject.} = `resSym`.unsafeGetErr()[]
      `errBody`

proc mapErr*[V, E, F](res: sink Result[V, E],
                      fn: proc(val: E): F): Result[V, F] {.effectsOf: fn.} =
  if res.unsuccessful():
    return failure[V, F](fn(res.err))
  return success[V, F](res.val)
macro mapErrIt*[V, E](res: sink Result[V, E], errBody: untyped): untyped =
  let
    resSym = genSym(ident = "res")
    eSym = genSym(nskType, ident = "E")
  quote do:
    type
      `eSym` = typeof(block:
        var it {.inject, noinit.}: typeof(`res`.getErr())
        `errBody`)
    let `resSym` = `res`
    if `resSym`.unsuccessful():
      failure[`resSym`.V, `eSym`](block:
        let it {.inject.} = `resSym`.unsafeGetErr()[]
        `errBody`)
    else:
      success[`resSym`.V, `eSym`](`resSym`.unsafeGetVal()[])
