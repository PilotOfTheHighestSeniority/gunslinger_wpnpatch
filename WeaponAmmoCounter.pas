unit WeaponAmmoCounter;

{$define DISABLE_AUTOAMMOCHANGE}  //��������� �������������� ����� ���� �������� �� ������� ������� ������� ��� ��������� �������� �������� ����; ��� ������ ���������� ���������, ����� � ��������� ��������� ������!

interface
  procedure CWeaponMagazined__OnAnimationEnd_DoReload(wpn:pointer); stdcall;
  function CWeaponShotgun__OnAnimationEnd_OnAddCartridge(wpn:pointer):boolean; stdcall;  

function Init:boolean;

implementation
uses BaseGameData, WeaponAdditionalBuffer, HudItemUtils, xr_Cartridge, ActorUtils, strutils, ActorDOF, gunsl_config, sysutils, dynamic_caster, xr_strings;


procedure SwapFirstLastAmmo(wpn:pointer);stdcall;
var
  cs, ce:pCCartridge;
  tmp:CCartridge;
  cnt:cardinal;
begin
  if ((GetGLStatus(wpn)=1) or (IsGLAttached(wpn))) and IsGLEnabled(wpn) then exit;
  cnt:=GetAmmoInMagCount(wpn);
  if cnt>1 then begin
    cnt:=cnt-1;
    cs:=GetCartridgeFromMagVector(wpn,0);
    ce:=GetCartridgeFromMagVector(wpn,cnt);
    CopyCartridge(cs^, tmp);
    CopyCartridge(ce^, cs^);
    CopyCartridge(tmp, ce^);
  end;
end;

procedure SwapLastPrevAmmo(wpn:pointer);stdcall;
var
  cs, ce:pCCartridge;
  tmp:CCartridge;
  cnt:cardinal;
begin
  if ((GetGLStatus(wpn)=1) or (IsGLAttached(wpn))) and IsGLEnabled(wpn) then exit;
  cnt:=GetAmmoInMagCount(wpn);
  if cnt>1 then begin
    cnt:=cnt-1;
    cs:=GetCartridgeFromMagVector(wpn,cnt-1);
    ce:=GetCartridgeFromMagVector(wpn,cnt);
    CopyCartridge(cs^, tmp);
    CopyCartridge(ce^, cs^);
    CopyCartridge(tmp, ce^);
  end;
end;


//---------------------------------------------------���� ����� �������� � �������-------------------------
procedure CWeaponMagazined__OnAnimationEnd_DoReload(wpn:pointer); stdcall;
var
  buf: WpnBuf;
  def_magsize, mod_magsize, curammocnt:integer;
begin
  buf:=GetBuffer(wpn);
  //���� ������ ��� ��� �� ��� ������������c� ��� � ��� ����� ��������� - ������ ���������� �� ������
  if (buf=nil) then begin virtual_CWeaponMagazined__ReloadMagazine(wpn); exit; end;

  if buf.IsReloaded() then begin buf.SetReloaded(false); exit; end;
  if (((GetGLStatus(wpn)=1) or (IsGLAttached(wpn))) and IsGLEnabled(wpn)) then begin virtual_CWeaponMagazined__ReloadMagazine(wpn); exit; end;

  //���������, ����� ������ �������� � ������ � ������� �������� � ��� ������
  def_magsize:=GetMagCapacityInCurrentWeaponMode(wpn);
  curammocnt:=GetCurrentAmmoCount(wpn);

  //������ ��������� �� ��������� ������ � ��������, ������� �������� � ���� ���������
  if IsWeaponJammed(wpn) then begin
    SetAmmoTypeChangingStatus(wpn, $FF);
    mod_magsize:=curammocnt;
  end else if IsBM16(wpn) then begin
    mod_magsize:=buf.ammo_cnt_to_reload;
  end else if not IsGrenadeMode(wpn) and buf.IsAmmoInChamber() and ((curammocnt=0) or ((GetAmmoTypeChangingStatus(wpn)<>$FF) and not buf.SaveAmmoInChamber() )) then begin
    mod_magsize:=def_magsize-1;
  end else begin
    mod_magsize:=def_magsize;
  end;

  //������� ������� ��������, ������������ �� ��� � ����������� ������ ��������
  SetMagCapacityInCurrentWeaponMode(wpn, mod_magsize);
  virtual_CWeaponMagazined__ReloadMagazine(wpn);
  SetMagCapacityInCurrentWeaponMode(wpn, def_magsize);
end;


procedure CWeaponMagazined__OnAnimationEnd_DoReload_Patch(); stdcall;
asm
  pushad
    sub esi, $2e0
    push esi
    call CWeaponMagazined__OnAnimationEnd_DoReload
  popad
end;


//---------------------------------------------------������� ���� ������� � ���������� � �������-------------------------
procedure NeedNotUnloadLastCartridge(wpn:pointer); stdcall;
var
  buf:WpnBuf;
begin
  buf:=GetBuffer(wpn);
  if
    not IsGrenadeMode(wpn)
  and
    (buf<>nil)    
  and
    buf.IsAmmoInChamber()
  and
    buf.SaveAmmoInChamber()

  then begin
    SwapFirstLastAmmo(wpn);
    buf.is_firstlast_ammo_swapped:=true;
    ChangeAmmoVectorStart(wpn, sizeof(CCartridge));
    virtual_CWeaponMagazined__UnloadMagazine(wpn, true);
    ChangeAmmoVectorStart(wpn, (-1)*sizeof(CCartridge));    
  end else begin
    if buf <> nil then begin
      buf.is_firstlast_ammo_swapped:=false;
    end;
    virtual_CWeaponMagazined__UnloadMagazine(wpn, true);
  end;
end;

procedure CWeaponMagazined__ReloadMagazine_OnUnloadMag_Patch(); stdcall;
asm
  pushad
    push esi
    call NeedNotUnloadLastCartridge
  popad
  @finish:
end;

procedure CWeaponMagazined__ReloadMagazine_OnFinish(wpn:pointer); stdcall;
var
  buf:WpnBuf;
begin
  buf:=GetBuffer(wpn);
  if (buf<>nil) and (buf.is_firstlast_ammo_swapped) then begin
    buf.is_firstlast_ammo_swapped:=false;
    SwapFirstLastAmmo(wpn);
  end;
end;

procedure CWeaponMagazined__ReloadMagazine_OnFinish_Patch(); stdcall;
asm
  pushad
    push esi
    call CWeaponMagazined__ReloadMagazine_OnFinish
  popad

  pop esi
  pop ebp
  add esp, $48
end;


{$ifdef DISABLE_AUTOAMMOCHANGE}
procedure CWeaponmagazined__TryReload_Patch();stdcall;
asm
  //���������, ���� �� �� ����� ������� �� ����� ������

  cmp byte ptr [esi+$6C7], $FF //if m_set_next_ammoType_on_reload<>-1 then jmp
  jne @orig
  mov eax, 0                    //�������, ��� � ������ 0 ��������� ����� �������� ;)

  @orig:
  //������ ����������
  sar eax, 02
  test al, al
  ret
end;

procedure CWeaponShotgun__HaveCartridgeInInventory_Patch(); stdcall;
asm
  cmp byte ptr [esi+$6c7], $FF
  je @false

  mov [esi+$6C7], bl
  mov eax, 1
  jmp @finish

  @false:
  xor eax, eax
  
  @finish:
  pop ebx
  cmp edi, ebp  //??? �� ��� � ���������
  pop edi
  pop ebp
  pop esi
  ret 4
end;
{$endif}

//---------------------------------������� � ���������� ��� ����������----------------------------

function CWeaponShotgun__OnAnimationEnd_OnAddCartridge(wpn:pointer):boolean; stdcall;
//����������, ����� �� ���������� �������� ������� � TriStateReload, ��� ������ ��� :)
var
  buf:WpnBuf;
begin
  buf:=GetBuffer(wpn);
  if buf<>nil then begin
    if not buf.IsReloaded then begin
      virtual_CWeaponShotgun__AddCartridge(wpn, 1);
      if buf.IsAmmoInChamber() and buf.SaveAmmoInChamber() then begin
        SwapLastPrevAmmo(wpn);
      end;
    end;
  end else begin
    virtual_CWeaponShotgun__AddCartridge(wpn, 1); //���� ������������� ���� ;)
  end;
  result:=CWeaponShotgun__HaveCartridgeInInventory(wpn, 1);
end;

procedure CWeaponShotgun__OnAnimationEnd_OnAddCartridge_Patch(); stdcall;
asm
  pushad
    sub esi, $2e0
    push esi
    call CWeaponShotgun__OnAnimationEnd_OnAddCartridge
    cmp al, 01
  popad
end;

//-----------------------------------------anm_close � ������ ������� ���������� �������----------------------------
procedure CWeaponShotgun__Action_OnStopReload(wpn:pointer); stdcall;
begin
  if (GetSubState(wpn)=EWeaponSubStates__eSubStateReloadEnd) or (IsWeaponJammed(wpn)) then begin //???������ ������� �� ���������� - �� �������� �����???
    exit;
  end;
  if not IsActionProcessing(wpn) then begin
    SetSubState(wpn, EWeaponSubStates__eSubStateReloadEnd);
    virtual_CHudItem_SwitchState(wpn,EWeaponStates__eReload);
  end else begin
    SetActorKeyRepeatFlag(kfFIRE, true);
  end;
end;

procedure CWeaponShotgun__Action_OnStopReload_Patch(); stdcall;
asm
  pushad
  push esi
  call CWeaponShotgun__Action_OnStopReload
  popad
end;

//----------------------------------------------���������� ������� � open-------------------------------------------
procedure CWeaponMagazined__OnAnimationEnd_anm_open(wpn:pointer); stdcall;
var
  buf:WpnBuf;
begin
  if IsWeaponJammed(wpn) then begin
    SetWeaponMisfireStatus(wpn, false);
    SetSubState(wpn, EWeaponSubStates__eSubStateReloadBegin);
    virtual_CHudItem_SwitchState(wpn, EHudStates__eIdle);
    exit;
  end;

  SetSubState(wpn, EWeaponSubStates__eSubStateReloadInProcess); //����������
  buf:=GetBuffer(wpn);
  if (buf<>nil) and buf.AddCartridgeAfterOpen() then begin
    CWeaponShotgun__OnAnimationEnd_OnAddCartridge(wpn);
  end;
  virtual_CHudItem_SwitchState(wpn, EWeaponStates__eReload);
end;

procedure CWeaponMagazined__OnAnimationEnd_anm_open_Patch(); stdcall;
asm
  pushad
  sub esi, $2e0
  push esi
  call CWeaponMagazined__OnAnimationEnd_anm_open
  popad
end;

//-------------------------------------------------------������� �� ������� ��� �������� � ���������-----------------------------------------
function CWeaponShotgun_Needreload(wpn:pointer):boolean; stdcall;
begin
  result:= (IsWeaponJammed(wpn) or CWeaponShotgun__HaveCartridgeInInventory(wpn, 1));
end;

procedure CWeaponShotgun__TriStateReload_Needreload_Patch(); stdcall;
asm
  pushad
    push esi
    call CWeaponShotgun_Needreload
    test al, al
  popad
end;

procedure CWeaponShotgun__OnStateSwitch_Needreload_Patch(); stdcall;
asm
  pushad
    push edi
    call CWeaponShotgun_Needreload
    test al, al
  popad
end;


procedure CWeaponMagazined__TryReload_hasammo_Patch(); stdcall;
asm
  cmp [esi+$690], 00 //original
  jne @finish
  //cmp byte ptr [esi+$7f8], 1 //������� �� �������� ������
  pushad
    push esi
    call IsGrenadeMode
    cmp al, 1
  popad

  @finish:
end;
//------------------------------------------------------------------------------------------------------------------
procedure CWeapon__Weight_CalcAmmoWeight(wpn:pointer; total_weight:psingle); stdcall;
var
  weight:single;
  cnt, i:cardinal;
  c:pCCartridge;
  box_weight, box_count:single;
  sect:PChar;
begin
  if dynamic_cast(wpn, 0, RTTI_CWeapon, RTTI_CWeaponMagazined, false) = nil then exit;

  weight:=0;

  cnt:=GetAmmoInMagCount(wpn);
  if cnt>0 then begin
    for i:=0 to cnt-1 do begin
      c:=GetCartridgeFromMagVector(wpn, i);
      if c<>nil then begin
        sect:= GetCartridgeSection(c);
        if sect<>nil then begin
          box_count:=game_ini_r_single_def(sect, 'box_size', 1);
          box_weight:=game_ini_r_single_def(sect, 'inv_weight', 0);

          weight:=weight+ (box_weight/box_count);
        end;
      end;
    end;
  end;

  cnt:=GetAmmoInGLCount(wpn);
  if cnt>0 then begin
    for i:=0 to cnt-1 do begin
      c:=GetGrenadeCartridgeFromGLVector(wpn, i);
      if c<>nil then begin
        sect:= GetCartridgeSection(c);
        if sect<>nil then begin
          box_count:=game_ini_r_single_def(sect, 'box_size', 1);
          box_weight:=game_ini_r_single_def(sect, 'inv_weight', 0);

          weight:=weight+ (box_weight/box_count);
        end;
      end;
    end;
  end;

  total_weight^:=total_weight^+weight;
end;


procedure CWeapon__Weight_CalcAmmoWeight_Patch(); stdcall;
asm
  lea eax, [esp+8]
  pushad

  push eax
  push esi
  call CWeapon__Weight_CalcAmmoWeight


  xor eax, eax
  cmp eax, 0 //����� ����������� ������� �������� ���� �� ����� �����������!
  popad;
end;

function GetTotalGrenadesCountInInventory(wpn:pointer):cardinal;stdcall;
var
  g_m:boolean;
  cnt, i:cardinal;
begin
  if (GetGLStatus(wpn)=0) or ((GetGLStatus(wpn)=2) and not IsGLAttached(wpn)) then begin
    result:=0;
    exit;
  end;

  g_m:=IsGLEnabled(wpn);
  cnt:=GetGLAmmoTypesCount(wpn);
  result:=0;

  for i:=0 to cnt-1 do begin
    if g_m then
      result:=result+cardinal(CWeapon__GetAmmoCount(wpn, byte(i)))
    else
      result:=result+cardinal(CWeaponMagazinedWGrenade__GetAmmoCount2(wpn, byte(i)));
  end;
end;

procedure CWeaponMagazinedWGrenade__GetBriefInfo_GrenadesCount_Patch(); stdcall;
asm
  push ecx
  lea ecx, [esp]
  pushad
    push ecx

    push ebp
    call GetTotalGrenadesCountInInventory

    pop ecx
    mov [ecx], eax
  popad
  pop eax
end;

function CWeaponMagazined_FillBriefInfo(wpn:pointer; bi:pII_BriefInfo):boolean; stdcall;
//no GL
var
  ammo_sect:PChar;
  s:string;
  cnt, ammos, i, current:cardinal;
  queue:integer;
begin
  ammo_sect:= GetMainCartridgeSectionByType(wpn, GetAmmoTypeIndex(wpn, false));
//  if GetAmmoInMagCount(wpn)>0 then begin
//    ammo_sect:=@(GetCartridgeFromMagVector(wpn, GetAmmoInMagCount(wpn)-1).m_ammo_sect.p_.value);
//  end;
  
  assign_string(@bi.name, game_ini_read_string(ammo_sect, 'inv_name_short'));
  assign_string(@bi.icon, ammo_sect);
  s:=inttostr(GetAmmoInMagCount(wpn));
  assign_string(@bi.cur_ammo, PChar(s));


  cnt:=GetMainAmmoTypesCount(wpn);
  if cnt>0 then begin
    current:=GetAmmoTypeIndex(wpn, false);
    s:=inttostr(CWeapon__GetAmmoCount(wpn, current));
    assign_string(@bi.fmj_ammo, PChar(s));
    if cnt>1 then begin
      ammos:=0;
      for i:=0 to cnt-1 do begin
        if i<>current then begin
          ammos:=ammos+cardinal(CWeapon__GetAmmoCount(wpn, i));
        end;
      end;
      s:=inttostr(ammos);
      assign_string(@bi.ap_ammo, PChar(s));
    end else begin
      assign_string(@bi.ap_ammo, ' ');
    end;
  end else begin
    assign_string(@bi.fmj_ammo, ' ');
    assign_string(@bi.ap_ammo, ' ');    
  end;

  if HasDifferentFireModes(wpn) then begin
    queue:=CurrentQueueSize(wpn);
    if queue<0 then begin
      s:='A';
    end else begin
      s:=inttostr(queue)
    end;
    assign_string(@bi.fire_mode, PChar(s));
  end else begin
    assign_string(@bi.fire_mode, ' ');
  end;
  assign_string(@bi.grenade, ' '); 

  result:=true;
end;


function CWeaponMagazinedWGrenade_FillBriefInfo(wpn:pointer; bi:pII_BriefInfo):boolean; stdcall;
var
  ammotypes, i:cardinal;
  ammo_cnt, queue:integer;
  g_m:boolean;
  ammo_sect:PChar;
  current:byte;
  s:string;  
begin
  g_m:=IsGrenadeMode(wpn);

  if not g_m then begin
    result:=CWeaponMagazined_FillBriefInfo(wpn, bi);
  end else begin
    current:=GetAmmoTypeIndex(wpn, false);
    ammo_sect:= GetGLCartridgeSectionByType(wpn, current);
    assign_string(@bi.name, game_ini_read_string(ammo_sect, 'inv_name_short'));
    assign_string(@bi.icon, ammo_sect);
    s:=inttostr(GetAmmoInGLCount(wpn));
    assign_string(@bi.cur_ammo, PChar(s));

    ammotypes:=GetGLAmmoTypesCount(wpn);
    if ammotypes>0 then begin
      s:=inttostr(CWeapon__GetAmmoCount(wpn, current));
      assign_string(@bi.fmj_ammo, PChar(s));
      if ammotypes>1 then begin
        ammo_cnt:=0;
        for i:=0 to ammotypes-1 do begin
          if i<>current then begin
            ammo_cnt:=ammo_cnt+cardinal(CWeapon__GetAmmoCount(wpn, i));
          end;
        end;
        s:=inttostr(ammo_cnt);
        assign_string(@bi.ap_ammo, PChar(s));
      end else begin
        assign_string(@bi.ap_ammo, ' ');
      end;
    end else begin
      assign_string(@bi.fmj_ammo, ' ');
      assign_string(@bi.ap_ammo, ' ');
    end;

    if HasDifferentFireModes(wpn) then begin
      queue:=CurrentQueueSize(wpn);
      if queue<0 then begin
        s:='A';
      end else begin
        s:=inttostr(queue)
      end;
      assign_string(@bi.fire_mode, PChar(s));
    end else begin
      assign_string(@bi.fire_mode, ' ');
    end;
    result:=true;
  end;

  //�������������� ������ ����� ����
  if (GetGLStatus(wpn)=1) or ((GetGLStatus(wpn)=2) and IsGLAttached(wpn)) then begin
    ammotypes:=GetGLAmmoTypesCount(wpn);
    ammo_cnt:=0;
    for i:=0 to ammotypes-1 do begin
      if not g_m then
        ammo_cnt:=ammo_cnt+CWeaponMagazinedWGrenade__GetAmmoCount2(wpn, i)
      else
        ammo_cnt:=ammo_cnt+CWeapon__GetAmmoCount(wpn, i);
    end;
    if ammo_cnt = 0 then begin
      assign_string(@bi.grenade, 'X');
    end else begin
      assign_string(@bi.grenade, PChar(inttostr(ammo_cnt)));
    end;
  end else begin
    assign_string(@bi.grenade, ' ');
  end;
end;

procedure CWeaponMagazined__GetBriefInfo_Replace_Patch(); stdcall;
asm
  mov eax, [esp+4]
  pushad
    push eax
    push ecx
    call CWeaponMagazined_FillBriefInfo;
  popad

  mov eax, 1
  ret 4
end;

procedure CWeaponMagazinedWGrenade__GetBriefInfo_Replace_Patch(); stdcall;
asm
  mov eax, [esp+4]
  pushad
    push eax
    push ecx
    call CWeaponMagazinedWGrenade_FillBriefInfo;
  popad

  mov eax, 1
  ret 4
end;

procedure CWeaponMagazinedWGrenade__PerformSwitchGL_ammoinverse_Patch(); stdcall;
asm
  //������� �������

  mov edi, [esi+$6C8]
  mov ebx, [esi+$7EC]
  mov [esi+$6C8], ebx
  mov [esi+$7EC], edi

  mov edi, [esi+$6CC]
  mov ebx, [esi+$7F0]
  mov [esi+$6CC], ebx
  mov [esi+$7F0], edi

  mov edi, [esi+$6D0]
  mov ebx, [esi+$7F4]
  mov [esi+$6D0], ebx
  mov [esi+$7F4], edi

  //������ ������� �������
  mov eax, [esi+$6cc]
  sub eax, [esi+$6c8]

  xor edx, edx
  mov ebx, $3c;
  div ebx

  mov [esi+$690], eax


  mov [esi+$69C], 0
  //�����
  pop edi
  pop esi
  pop ebp
  pop ebx
  add esp, $4C
  ret
end;


function Init:boolean;
var
    debug_bytes:array of byte;
    addr:cardinal;
begin
  result:=false;
  setlength(debug_bytes, 6);
  ////////////////////////////////////////////////////
  //[bug]��������� ��� � ������������ ������ ���� �������� ��� �����������, ����� � ��� �� ������� �������� �������� ���� �� ������� ��������
  //[bug]��� �� �����������, ���� � ������, � �������� �������� ������� ������ ���� ��������, � ������ ���� � ��������� ������ ���, ����������� ������� ��� �, �� ��������� ��������� �����,  ���������
  //����� ������� ������ �� ����� ����������� �� ������� ����� ����
  // ������� � ���, ��� � CWeaponMagazined::TryReload �� ����������� �������� ����� m_ammoType ������ m_set_next_ammoType_on_reload
  debug_bytes[0]:=$C7;
  if not WriteBufAtAdr(xrGame_addr+$2D0185, @debug_bytes[0],1) then exit;
  if not WriteBufAtAdr(xrGame_addr+$2DE84B, @debug_bytes[0],1) then exit;  //CWeaponShotgun::HaveCarteidgeInInventory, ����� ��� ����� ��������������, �� ����� �����


  //������, ������� �������� ���� �������� � ������� � ������ ��� ������
  addr:=xrGame_addr+$2CCD94;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__OnAnimationEnd_DoReload_Patch), 20, true) then exit;

  //������������ ���������� ������� ����� anm_open
  addr:=xrGame_addr+$2DE41C;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__OnAnimationEnd_anm_open_Patch), 15, true) then exit;

  //��� ����� ���� �������� ������� ����������� - ���������� �������� ��������� ������ �������������
  nop_code(xrGame_addr+$2D10D8, 2); //������� ������� �� ����������� ������ ���������� ������� � �����������
  addr:=xrGame_addr+$2D1106;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__ReloadMagazine_OnUnloadMag_Patch), 6, true) then exit;
  //������ ������ � ��������� ������, ���� � ��� ���� ����� ���� 
  addr:=xrGame_addr+$2D125F;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__ReloadMagazine_OnFinish_Patch), 6, false) then exit;

  //��������� ���������� "�������" ������� ��� ���������� ������� ��������� +���������� �������� anm_close (� CWeaponShotgun::Action)
  addr:=xrGame_addr+$2DE374;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__Action_OnStopReload_Patch), 30, true) then exit;

  //������ � ����������+�������� �������������+�������� �� ���������� ������� � �������
  addr:=xrGame_addr+$2DE3ED;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__OnAnimationEnd_OnAddCartridge_Patch), 22, true) then exit;

  //������� �������, ������� �� ���� ������������ CWeaponMagazined, ���� �������� � ���� ��� �� � ���������, �� � ��������
  //��� ����������� ������ ��� ����������� � ������ ���������
  addr:=xrGame_addr+$2D00AD;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__TryReload_hasammo_Patch), 7, true) then exit;


  //����� ����������� ������������ ��������, ����� � ��������� ��� ��������
  addr:=xrGame_addr+$2DE94A;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__TriStateReload_Needreload_Patch), 11, true) then exit;
  addr:=xrGame_addr+$2DE9D1;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__OnStateSwitch_Needreload_Patch), 11, true) then exit;
  addr:=xrGame_addr+$2DEA19;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__OnStateSwitch_Needreload_Patch), 11, true) then exit;
  //addr:=xrGame_addr+$2DEA00;
  //if not WriteJump(addr, cardinal(@CWeaponShotgun__OnStateSwitch_Needreload_Patch), 11, true) then exit;


{$ifdef DISABLE_AUTOAMMOCHANGE}
  addr:=xrGame_addr+$2D00FF;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__TryReload_Patch), 5, true) then exit;

  addr:=xrGame_addr+$2DE849;
  if not WriteJump(addr, cardinal(@CWeaponShotgun__HaveCartridgeInInventory_Patch), 6, false) then exit;
{$endif}

  //[bug] ��� � ������������ �������� ���� ������ � CWeapon::Weight: �� ����������� ����������� ������� � �������� ����������� ������ �����, � ����� ������� � �������������
  addr:=xrGame_addr+$2BE9B7;
  if not WriteJump(addr, cardinal(@CWeapon__Weight_CalcAmmoWeight_Patch), 7, true) then exit;

  //[bug] ��� � ������������ ����� ������ ��� ��������� - ������������ ������ ����� ��� 1�� ����, ��������� ���������
  addr:=xrGame_addr+$2D2562;
  if not WriteJump(addr, cardinal(@CWeaponMagazinedWGrenade__GetBriefInfo_GrenadesCount_Patch), 17, true) then exit;


  //��������� ����� BriefInfo
  addr:=xrGame_addr+$2CE360;
  if not WriteJump(addr, cardinal(@CWeaponMagazined__GetBriefInfo_Replace_Patch), 5, false) then exit;
  addr:=xrGame_addr+$2D2110;
  if not WriteJump(addr, cardinal(@CWeaponMagazinedWGrenade__GetBriefInfo_Replace_Patch), 5, false) then exit;


  //[bug] ��� � ��������� ������� �������� � �������� ��� ������������ �� �������� � ������� - thanks to Shoker
  addr:=xrGame_addr+$2D3810;
  if not WriteJump(addr, cardinal(@CWeaponMagazinedWGrenade__PerformSwitchGL_ammoinverse_Patch), 6, false) then exit;


  setlength(debug_bytes, 0);  
  result:=true;

end;

end.
