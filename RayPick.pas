unit RayPick;

interface
uses MatVectors;
type rq_result=packed record
  O:pointer;
  range:single;
  element:integer;
end;
type prq_result=^rq_result;

type rq_results=packed record
  vec_start:prq_result;
  vec_end:prq_result;
  vec_memend:prq_result;
end;
type prq_results=^rq_results;

type collide__ray_defs = packed record
  start:FVector3;
  dir:FVector3;
  range:single;
  flags:cardinal;
  tgt:cardinal;
end;
type pcollide__ray_defs=^collide__ray_defs;

type SPickParam = packed record
  RQ:rq_result;
  power:single;
  pass:cardinal;
end;
type pSPickParam=^SPickParam;

type rq_callback = function (res:prq_result; data:pointer):boolean;stdcall;

function Level_RayPick(start:pFVector3; dir:pFVector3; range:single; tgt:cardinal; R:prq_result; ignore_object:pointer):boolean; stdcall;
function Level_RayQuery(R:pcollide__ray_defs; CB:pointer; params:pointer; tb:pointer; ignore_object:pointer):boolean; stdcall;

function Init():boolean;

const
  rq_target__rqtNone:cardinal = 0;
  rq_target__rqtObject:cardinal = 1;
  rq_target__rqtStatic:cardinal = 2;
  rq_target__rqtShape:cardinal = 4;
  rq_target__rqtObstacle:cardinal = 8;
  rq_target__rqtBoth:cardinal = 3;
  rq_target__rqtDyn:cardinal = 13;

implementation
uses BaseGameData, Level, Misc, sysutils;
var
  rqres:rq_results;
  prqres:prq_results;

function Level_RayPick(start:pFVector3; dir:pFVector3; range:single; tgt:cardinal; R:prq_result; ignore_object:pointer):boolean; stdcall;
asm
  pushad
  call GetLevel
  push eax
  call Level_to_CObjectSpace

  push ignore_object
  push r
  push tgt
  push range
  push dir
  push start
  mov ecx, eax
  mov eax, xrCDB_addr
  add eax, $13040
  call eax
  mov @result, al
  popad
end;

function Level_RayQuery(R:pcollide__ray_defs; CB:pointer; params:pointer; tb:pointer; ignore_object:pointer):boolean; stdcall;
asm
  pushad
  call GetLevel
  push eax
  call Level_to_CObjectSpace
  push ignore_object
  push tb
  push params
  push CB
  push R
  push prqres
  mov ecx, eax
  mov eax, xrCDB_addr
  add eax, $132b0
  call eax
  mov @result, al

  popad
end;



function Init():boolean;
begin


  //todo:��������-��������, � �������?
  result:=true;
  rqres.vec_start:=xrMemory__allocate(sizeof(rqres));
  rqres.vec_end:=rqres.vec_start;
  rqres.vec_memend:=prq_result(cardinal(rqres.vec_start)+sizeof(rqres));
  prqres:=@rqres;

  log(inttohex(cardinal(rqres.vec_start), 8));
end;
end.
