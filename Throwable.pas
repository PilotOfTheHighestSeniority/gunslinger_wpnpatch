unit Throwable;
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

//�������� �������� ����� ������ �� ����� � �����.

interface

function Init():boolean;
procedure ResetActivationHoldState(); stdcall;
procedure SetForcedQuickthrow(status:boolean);
function GetForcedQuickthrow():boolean;

procedure SetThrowForce(CMissile:pointer; force:single); stdcall;
procedure PrepareGrenadeForSuicideThrow(CMissile:pointer; force:single); stdcall;
procedure SetImmediateThrowStatus(CMissile:pointer; status:boolean); stdcall;
procedure SetConstPowerStatus(CMissile:pointer; status:boolean); stdcall;
function IsMissileInSuicideState(CMissile:pointer):boolean; stdcall;
function IsGrenadeDeactivated(CGrenade:pointer):boolean; stdcall;

procedure CMissile__SetDestroyTimeMax(CMissile:pointer; time:cardinal); stdcall;
function CMissile__GetDestroyTimeMax(CMissile:pointer):cardinal; stdcall;

function CMissile__GetDestroyTime(CMissile:pointer):cardinal; stdcall;
procedure CMissile__SetDestroyTime(CMissile:pointer; time_moment:cardinal); stdcall;
function virtual_CGrenade_DropGrenade(CGrenade:pointer):boolean; stdcall;

const
		EMissileStates__eThrowStart:cardinal = 5;
		EMissileStates__eReady:cardinal = 6;
		EMissileStates__eThrow:cardinal = 7;
		EMissileStates__eThrowEnd:cardinal = 8;

    CMISSILE_NOT_ACTIVATED:cardinal=$FFFFFFFF;

implementation
uses BaseGameData, Misc, WeaponSoundLoader, ActorUtils, HudItemUtils, gunsl_config, KeyUtils, sysutils, strutils, dynamic_caster, HitUtils, DetectorUtils, xr_BoneUtils, ControllerMonster, WeaponEvents, MatVectors, physics;

var
  _activate_key_state:TKeyHoldState;
  _quick_throw_forced:boolean;

const
  GRENADE_KEY_HOLD_TIME_DELTA:cardinal = 350; //������ �������, ��������� ������� � ������� �������� �������� �� ��������� � ������� ���������

function CMissile__GetFakeMissile(CMissile:pointer):pointer; stdcall;
asm
  mov eax, CMissile
  mov eax, [eax+$394]
end;

function CMissile__GetDestroyTime(CMissile:pointer):cardinal; stdcall;
asm
  mov eax, CMissile
  test eax, eax
  je @null

  mov eax, [eax+$340]
  mov @result, eax
  jmp @finish
  
  @null:
  mov @result, $FFFFFFFF

  @finish:
end;


function CMissile__GetDestroyTimeMax(CMissile:pointer):cardinal; stdcall;
asm
  mov eax, CMissile
  test eax, eax
  je @null

  mov eax, [eax+$344]
  mov @result, eax
  jmp @finish
  
  @null:
  mov @result, $FFFFFFFF

  @finish:
end;

procedure CMissile__SetDestroyTime(CMissile:pointer; time_moment:cardinal); stdcall;
asm
  push eax
  push ebx

  mov eax, CMissile
  test eax, eax
  je @finish

  mov ebx, time_moment
  add eax, $340
  mov [eax], ebx

  @finish:
  pop ebx
  pop eax
end;

procedure CMissile__SetDestroyTimeMax(CMissile:pointer; time:cardinal); stdcall;
asm
  pushad

  mov eax, CMissile
  test eax, eax
  je @finish

  mov ebx, time
  mov [eax+$344], ebx

  @finish:
  popad
end;

procedure CMissile__spawn_fake_missile(CMissile:pointer); stdcall;
asm
  pushad
    mov ecx, CMissile
    mov eax, xrgame_addr
    add eax, $2c7e20
    call eax
  popad
end;

procedure CMissile__set_m_throw(this:pointer; status:boolean); stdcall;
asm
  pushad
    mov ecx, this
    movzx eax, status
    mov [ecx+$33c], eax
  popad
end;

function CMissile__Useful(this:pointer):boolean; stdcall;
asm
  pushad
    mov ecx, this
    mov eax, xrgame_addr
    add eax, $2c5c80
    call eax
    mov @result, al
  popad
end;
// 0x33C - bool m_throw
// 0x344 - m_dwDestroyTimeMax
// 0x348 - Fvector m_throw_direction;
// 0x354 - Fmatrix m_throw_matrix;
// 0x394 - CMissile	*m_fake_missile;
// 0x398 - float m_fMinForce,
// 0x39c - float m_fConstForce,
// 0x3a0 - float m_fMaxForce,
// 0x3a4 - float m_fForceGrowSpeed;
// 0x3a8 - bool m_constpower;
// 0x3ac - float m_fThrowForce;

procedure PrepareGrenadeForSuicideThrow(CMissile:pointer; force:single); stdcall;
asm
  pushad
    mov ecx, CMissile
    lea eax, [force]
    mov eax, [eax]
    xor ebx, ebx
    mov [ecx+$398], ebx // m_fMinForce
    mov [ecx+$3ac], eax // m_fThrowForce
    mov [ecx+$39c], eax // m_fConstForce
  popad
end;

procedure SetImmediateThrowStatus(CMissile:pointer; status:boolean); stdcall;
asm
  pushad
    mov ecx, CMissile
    movzx eax, [status]
    mov [ecx+$33c], eax // m_throw
  popad
end;

procedure SetConstPowerStatus(CMissile:pointer; status:boolean); stdcall;
asm
  pushad
    mov ecx, CMissile
    movzx eax, [status]
    mov [ecx+$3a8], eax
  popad
end;

procedure SetupQuickThrowForceParams(CMissile:pointer); stdcall;
asm
  push eax
  push ecx
    mov ecx, CMissile
    pushad
      call IsActorPlanningSuicide
      cmp al, 1
    popad
    je @controlled
    mov eax, [ecx+$39c]
    mov [ecx+$3ac], eax //�������� ���� ������, �������������� ��� ������� ���
    jmp @finish
    @controlled:
    push $40000000
    push ecx
    call PrepareGrenadeForSuicideThrow
    @finish:
  pop ecx
  pop eax
end;

procedure SetThrowForce(CMissile:pointer; force:single); stdcall;
asm
  pushad
    mov ecx, CMissile
    movss xmm0, force
    movss [ecx+$39c], xmm0
  popad
end;

function CGrenade__GetDetonationTresholdHit(this:pointer):single; stdcall;
asm
  mov eax, this
  test eax, eax
  je @null

  mov eax, [eax+$4bc]
  mov @result, eax
  jmp @finish

  @null:
  mov @result, 0

  @finish:
end;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
procedure CMissile__Load(CMissile:pointer; section:PChar; hsc:pHUD_SOUND_COLLECTION);stdcall;
begin
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_draw', 'sndDraw', 0, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_holster', 'sndHide', 0, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_throw_begin', 'sndThrowBegin', 0, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_throw', 'sndThrow', 0, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_throw_quick', 'sndThrowQuick', 0, $FFFFFFFF);

  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_sprint_start', 'sndSprintStart', 1, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_sprint_end', 'sndSprintEnd', 1, $FFFFFFFF);

  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_headlamp_on', 'sndHeadlampOn', 1, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_headlamp_off', 'sndHeadlampOff', 1, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_nv_on', 'sndNVOn', 1, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_nv_off', 'sndNVOff', 1, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_kick', 'sndKick', 1, $FFFFFFFF);

  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_suicide_begin', 'sndSuicideBegin', 1, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_suicide_throw', 'sndSuicideThrow', 1, $FFFFFFFF);
  HUD_SOUND_COLLECTION__LoadSound(hsc, section, 'snd_suicide_stop', 'sndSuicideStop', 1, $FFFFFFFF);
end;

procedure CMissile__Load_Patch();stdcall;
asm
  fstp[esi+$398]//����������
  pushad
    lea edx, [esi+$324]
    push edx        // HUD_SOUND_COLLECTION
    push edi        //char* section
    push esi        //this
    call CMissile__Load
  popad
  ret
end;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

function CMissile__State_anm_show_selector(CMissile:pointer):PChar; stdcall;
var
  act:pointer;
  snd, sect:PChar;
  curslot:integer;
  isquickthrow:boolean;
begin
  result:='anm_show';
  snd:='sndDraw';
  isquickthrow:=false;

  act:=GetActor();
  if (act<>nil) and (GetOwner(CMissile)=act) then begin
    player_hud__attach_item(CMissile); //��� �������� � ����������� �������� ���������
    ResetActorFlags(act);
//    UpdateSlots(act);
    if _activate_key_state.IsActive and _activate_key_state.IsHoldContinued then begin
      _activate_key_state.IsActive:=false;
      sect:=GetSection(CMissile);
      if game_ini_r_bool_def(sect, 'supports_quick_throw', false) and not IsActorControlled() and not IsActorSuicideNow() and not IsActorPlanningSuicide() then begin
        //���� ��������� ������� ������
        isquickthrow:=true;
        result:='anm_throw_quick';
        snd:='sndThrowQuick';
        CMissile__spawn_fake_missile(CMissile);
        SetupQuickThrowForceParams(CMissile);
      end;
    end;

    if not isquickthrow then begin
      ForgetDetectorAutoHide();
    end;

    if isquickthrow then begin
      StartCompanionAnimIfNeeded('quickthrow', CMissile, false)
    end else begin
      StartCompanionAnimIfNeeded('draw', CMissile, false)    
    end;
  end;
  CHudItem_Play_Snd(CMissile, snd);
end;

function CMissile__State_anm_hide_selector(CMissile:pointer):PChar; stdcall;
var
  act, det:pointer;
  det_anim:string;
begin
  result:='anm_hide';
  act:=GetActor();
  if (act<>nil) and (GetOwner(CMissile)=act) then begin
    ResetActorFlags(act);

    StartCompanionAnimIfNeeded('hide', CMissile, false);
  end;
  CHudItem_Play_Snd(CMissile, 'sndHide');
end;

function IsMissileInSuicideState(CMissile:pointer):boolean; stdcall;
begin
  result:=(leftstr(GetActualCurrentAnim(CMissile), length('anm_suicide')) = 'anm_suicide');
end;

function CMissile__State_anm_selector_dispatcher(CMissile:pointer; ret_addr:cardinal):PChar; stdcall;
var
  is_suicide_anim, is_suicide_allowed:boolean;
begin
  result:='anm_unknown';
  ret_addr:=ret_addr and $0000FFFF;


  case ret_addr of
    $75AA:result:=CMissile__State_anm_show_selector(CMissile);
    $7629:result:=CMissile__State_anm_hide_selector(CMissile);
    $76B4:begin
            //�������� ������ ������
            if IsActorControlled() and game_ini_r_bool_def(GetHudSection(CMissile), 'allow_suicide', false) then begin
              result:='anm_suicide_begin';
              CHudItem_Play_Snd(CMissile, 'sndSuicideBegin');
              StartCompanionAnimIfNeeded('suicide_begin', CMissile, true);
              SetConstPowerStatus(CMissile, true);
              SetImmediateThrowStatus(CMissile, true);
            end else begin
              result:='anm_throw_begin';
              CHudItem_Play_Snd(CMissile, 'sndThrowBegin');
              StartCompanionAnimIfNeeded('throw_begin', CMissile, true);
            end;
          end;
    $7740:begin
            //�������� ���������� ������
            is_suicide_anim:=IsMissileInSuicideState(CMissile);
            is_suicide_allowed:=game_ini_r_bool_def(GetHudSection(CMissile), 'allow_suicide', false);
            log('throw select, cur anim is '+GetActualCurrentAnim(CMissile));
            if is_suicide_allowed and is_suicide_anim and IsActorControlled() then begin
              //������� ������. �������� �������.
              log('anm_suicide_throw');
              NotifySuicideShotCallbackIfNeeded();

              result:='anm_suicide_throw';
              CMissile__SetDestroyTimeMax(CMissile, game_ini_r_int_def(GetSection(CMissile), 'suicide_success_destroy_time', CMissile__GetDestroyTimeMax(CMissile)));
              PrepareGrenadeForSuicideThrow(CMissile, game_ini_r_single_def(GetSection(CMissile), 'suicide_success_force', 20));
              virtual_Action(CMissile, kWPN_ZOOM, kActRelease);
                            
              CHudItem_Play_Snd(CMissile, 'sndSuicideThrow');
              StartCompanionAnimIfNeeded('suicide_throw', CMissile, true);

            end else if is_suicide_anim and is_suicide_allowed then begin
              log('anm_suicide_stop');
              NotifySuicideStopCallbackIfNeeded();

              //����������� ������, �� ����� ������. ���������� ���� ������ � ������ ������ ����� � �������
              result:='anm_suicide_stop';
              CMissile__SetDestroyTimeMax(CMissile, game_ini_r_int_def(GetSection(CMissile), 'suicide_fail_destroy_time', CMissile__GetDestroyTimeMax(CMissile)));              
              PrepareGrenadeForSuicideThrow(CMissile, game_ini_r_single_def(GetSection(CMissile), 'suicide_fail_force', 20));
              virtual_Action(CMissile, kWPN_ZOOM, kActRelease);

              CHudItem_Play_Snd(CMissile, 'sndSuicideStop');
              StartCompanionAnimIfNeeded('suicide_stop', CMissile, true);
            end else begin
              log('anm_throw');
              
              //������ ����������� ������
              result:='anm_throw';
              CHudItem_Play_Snd(CMissile, 'sndThrow');
              StartCompanionAnimIfNeeded('throw_end', CMissile, true);
            end;
          end;
  else
    log('CMissile__State_anm_selector_dispatcher: unknown call detected!', true);
  end;
end;

procedure CMissile__State_anm_Patch(); stdcall;
asm
    push 0                  //�������� ����� ��� �������� �����
    pushad
    pushfd
      push [esp+$28]
      push esi
      call CMissile__State_anm_selector_dispatcher  //�������� ������ � ������ �����
      mov ecx, [esp+$28]      //���������� ����� ��������
      mov [esp+$28], eax      //������ �� ��� ����� �������������� ������
      mov [esp+$24], ecx      //���������� ����� �������� �� 4 ����� ���� � �����
    popfd
    popad
    ret
end;

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function CMissile__OnActiveItem(CMissile:pointer):boolean; stdcall;
//��� ����������� true ��������� ���������� � ��������� ���������� � �������� ����������� �����
var
  curslot: integer;
  act:pointer;
begin
  result:=true;

  act:=GetActor();
  if (act=nil) or (act<>GetOwner(CMissile)) then exit;

  curslot:=GetActorActiveSlot();
  if curslot<>GetSlotOfActorHUDItem(act, CMissile) then begin
    ResetActivationHoldState();
    result:=false;         //�������� ����� �������� ����� �� ���� �����
    exit;
  end;

  if _quick_throw_forced then begin
    _activate_key_state.IsActive:=true;
    _activate_key_state.ActivationStart := GetGameTickCount();
    _activate_key_state.HoldDeltaTimePeriod:=GRENADE_KEY_HOLD_TIME_DELTA;    
    _activate_key_state.IsHoldContinued:=true;
    SetForcedQuickthrow(false);     
    result:=true;
    exit;
  end;

  if (curslot<0) or (curslot>6) then begin
    ResetActivationHoldState();
    SetForcedQuickthrow(false);
    exit;
  end;

  UpdateSlots(act);

  if not _activate_key_state.IsActive then begin
    _activate_key_state.IsActive:=true;
    _activate_key_state.ActivationStart := GetGameTickCount();
    _activate_key_state.HoldDeltaTimePeriod:=GRENADE_KEY_HOLD_TIME_DELTA;
    _activate_key_state.IsHoldContinued:=true;
  end;

  if not IsActionKeyPressedInGame(kDETECTOR+cardinal(curslot)) then begin
    //����� �������� �������, ��������� ���
    _activate_key_state.IsHoldContinued:=false;
  end;

  if {(GetActorPreviousSlot()>0) or} ((GetTimeDeltaSafe(_activate_key_state.ActivationStart)>_activate_key_state.HoldDeltaTimePeriod) or not _activate_key_state.IsHoldContinued) then begin
    result:=true;
  end else begin
    result:=false;
  end;
end;

procedure CMissile__OnActiveItem_Patch(); stdcall;
asm
  push 0
  pushad
    mov edx, [esp+$24]      //���������� ����� ��������
    mov [esp+$24], esi      //������������ push esi
    mov [esp+$20], edx      //���������� ����� �������� �� 4 ����� ���� � �����

    sub ecx, $2e0
    push ecx
    call CMissile__OnActiveItem
    cmp al, 1
  popad
  je @allok
  add esp, 8                //������  ���� ������ ��������������; �������� ����� �������� � ������ �� OnActiveItem
  ret

  @allok:                   //��������� � ��������� ����������
  mov esi, ecx
  mov eax, [esi]
  ret
end;

function CanHideGrenadeNow(CMissile:pointer):boolean; stdcall;
var
  state:cardinal;
begin
  result:=true;
  
  state:=GetCurrentState(CMissile);
  if (state=EMissileStates__eThrowStart) or (state=EMissileStates__eReady) or (state=EMissileStates__eThrow) or (state=EMissileStates__eThrowEnd) then begin
    result:=false;
    exit;
  end;

  if ((state=EHudStates__eShowing) and (GetActualCurrentAnim(CMissile)='anm_throw_quick')) then begin
    //�� ����� �������� ������� ������ �����
    //�� ���� ����� �� ������� �� ���� ��� ����� ������ ������ � ���� ������������� - �������� ����!
    result:=(GetActorSlotBlockedCounter(4)>0);
    exit;
  end;
end;

procedure CGrenade__SendHiddenItem_Patch();stdcall;
asm
  pushad
    sub esi, $2e0
    push esi
    call CanHideGrenadeNow
    cmp al, 0
  popad
  ret
end;

//DONE:����� ����� ����� ������ �����
procedure CMissile__PutNextToSlot(this:pointer; IsSameItemFound:boolean); stdcall;
var
  act:pointer;
  curslot, prevslot:integer;
begin
  act:=GetActor();
  if (act=nil) or (act<>GetOwner(this)) then exit;
  curslot:=GetActorActiveSlot();
  prevslot:=GetActorPreviousSlot();
  if (curslot<=0) or (curslot>6) then curslot:=-1;

  if not IsSameItemFound or ((GetActualCurrentAnim(this)='anm_throw_quick') and ((curslot<0) or not IsActionKeyPressedInGame(kDETECTOR+cardinal(curslot)))) then begin
    //����������� ��������� ��������� � ������, ������� ���� �� �������� ������
    RestoreLastActorDetector();

    if (prevslot>=0) and (ItemInSlot(act, prevslot)<>nil) then
      ActivateActorSlot(prevslot)
    else
      ActivateActorSlot(0);
  end else begin
    //�� ������ ������� ������ � ������ �������� � ��������� ��� ����; ������� ���, ����� �� ���� �������� ����� ��������� �������
    ActivateActorSlot(curslot);
    _activate_key_state.IsActive:=true;
    _activate_key_state.ActivationStart:=GetGameTickCount();
    _activate_key_state.HoldDeltaTimePeriod:=0;
  end
end;

procedure CMissile__PutNextToSlot_SameItemFound_Patch(); stdcall;
asm
  mov [ecx+$42], ax
  mov [ecx+$40], ax
  pushad
    push 01
    push esi
    call CMissile__PutNextToSlot
  popad
  ret
end;

procedure CMissile__PutNextToSlot_NoItem_Patch(); stdcall;
asm
  pushad
    push 00
    push esi
    call CMissile__PutNextToSlot
  popad
  ret
end;



//DONE: ����� ��� ������� �����������
procedure CMissile__ExitContactCallback(dxGeom:pointer); stdcall;
var
  grenade:pointer;
  sect:PChar;
  destroy_time, time_from_throw, now:cardinal;
  safe_time, delay_time:cardinal;
  samolikvidator_delta:cardinal;
  linear_vel:FVector3;
  cpsh:pointer;
  min_speed, speed:single;
  new_destroy_time:cardinal;
begin
  //������ ����� ����������, ��� � ��� ��������� �����, � �� ��, � ��� ��� ����������� ;)
  grenade:=dxGeomUserData__get_ph_ref_object(PHRetrieveGeomUserData(dxGeom));
  if grenade=nil then exit;
  grenade:=dynamic_cast(grenade, 0, RTTI_IPhysicsShellHolder, RTTI_CGrenade, false);
  if grenade=nil then exit;

  //��, � ��� ������������� �����... ���������, ������� ��� ������������ � ������� � ������� ������, � ���� ������� ���� - ������������ ��
  destroy_time:=CMissile__GetDestroyTime(grenade);
  now := GetGameTickCount();

  if (destroy_time=CMISSILE_NOT_ACTIVATED) or (destroy_time<=now) then exit;

  time_from_throw:=CMissile__GetDestroyTimeMax(grenade) - (destroy_time-now);

  sect:=GetSection(grenade);
  safe_time:=game_ini_r_int_def(sect, 'safe_time', 0);
  delay_time:=game_ini_r_int_def(sect, 'delay_time', 0);

  if (safe_time<>0) and (safe_time>time_from_throw) then begin
    CMissile__SetDestroyTime(grenade, CMISSILE_NOT_ACTIVATED);
  end else if (delay_time<>0) and (delay_time>time_from_throw) then begin
    //������ ���������� �������
  end else if game_ini_r_bool_def(sect, 'explosion_on_kick', false) then begin
    new_destroy_time:=now;
    min_speed:=game_ini_r_single_def(sect, 'min_explosion_speed', 0);
    if min_speed > 0 then begin
      cpsh:=dynamic_cast(grenade, 0, RTTI_CGrenade, RTTI_CPhysicsShellHolder, false);
      if cpsh <> nil then begin
        GetLinearVel(cpsh, @linear_vel);
        speed:=v_length(@linear_vel);
        if speed < min_speed then begin
          if game_ini_r_bool_def(sect, 'deactivate_on_minimal_speed_contact', false) then begin
            new_destroy_time:=CMISSILE_NOT_ACTIVATED;
          end else begin
            new_destroy_time:=destroy_time;
          end;
        end;
      end;
    end;
    CMissile__SetDestroyTime(grenade, new_destroy_time);
  end;
end;

procedure CMissile__ExitContactCallback_Patch(); stdcall;
asm
  pushad
    //���������, �������������� �� ���� ������� �����
    mov eax, [esp+$24]
    mov al, byte ptr [eax]
    cmp al, 0
    je @finish

    mov eax, [esp+$2C]  //mov eax, dContact& c
    push [eax+$50]      //c.geom.g1
    push [eax+$54]      //c.geom.g2

    call CMissile__ExitContactCallback
    call CMissile__ExitContactCallback

    @finish:
  popad
  ret
end;

//DONE: �������� ������ ������ � ��������� �����
procedure CMissile__shedule_update(this:pointer); stdcall;
var
  sect:PChar;
begin
  if not CMissile__Useful(this) then begin
    sect:=GetSection(this);
    if game_ini_line_exist(sect, 'checkout_bones') then begin
      SetWorldModelMultipleBonesStatus(this, game_ini_read_string(sect, 'checkout_bones'), false);
    end;
  end;
end;

procedure CMissile__shedule_update_Patch(); stdcall;
//���������� � ����� ������
asm
  pushad
    sub esi, $12C
    push esi
    call CMissile__shedule_update
  popad
  pop esi
  ret 4
end;


function CMissile__OnMotionMark(CMissile:pointer; state:cardinal):boolean;stdcall;
//������������ true �������� ������� �����, ����� - �� ������� ����
begin
  CHudItem__OnMotionMark(CMissile);
  result:=false;

  if (GetActualCurrentAnim(CMissile)='anm_throw_quick') then begin
    CMissile__set_m_throw(CMissile, false); //����� ����� ������ ��������� ��-�� ����, ��� ������ ��������� ��� - ����� ��������� � ������������ ������ � �� � ����� �� ����� ���������
    result:=true;
  end else if (state=EMissileStates__eThrow)  then begin
    result:=true;
  end;
end;

procedure CMissile__OnMotionMark_Patch;stdcall;
asm
  pushad
    push [esp+$28]          //push state
    sub ecx, $2e0
    push ecx
    call CMissile__OnMotionMark
    cmp al, 1
  popad
  ret
end;


//DONE: � CMissile::OnAnimationEnd ������� �������������� ���������� ������ ����, ������ ����� ������
function CMissile__OnAnimationEnd(CMissile:pointer; state:cardinal):boolean;stdcall;
//���� ��������� false - ������� �� ���� ���� OnAnimationEnd;  ���� ������ ���, �� ���� �� �������� ���������� ����� ���������!
var
  act:pointer;
begin
  result:=true;
  if IsMissileInSuicideState(CMissile) then begin
    SetConstPowerStatus(CMissile, true);
    SetImmediateThrowStatus(CMissile, true);
  end;

  act:=GetActor();
  if (state=EHudStates__eShowing) and (GetActualCurrentAnim(CMissile)='anm_throw_quick') then begin
    virtual_CHudItem_SwitchState(CMissile, EMissileStates__eThrowEnd);
    result:=false;
  end else if (act<>nil) and (act=GetOwner(CMissile)) and {(leftstr(GetActualCurrentAnim(CMissile), length('anm_idle'))='anm_idle')} (GetCurrentState(CMissile)=EHudStates__eIdle) then begin
    SetActorActionState(act, actModNeedMoveReassign, true);
  end;
end;

procedure CMissile__OnAnimationEnd_Patch;stdcall;
asm
  mov esi, [esp+$0C]  //������ �������� �������� ������
  pushad
    push esi          //� ��������� ��� ������ �����������
    sub ecx, $2e0
    push ecx
    call CMissile__OnAnimationEnd
    cmp al, 1
  popad
  je @finish
  add esp, 4          //�������� ��� ������� � OnAnimationEnd
  pop esi             //��������������� ����������� ������������ �����
  ret 4               //������������ �� OnAnimationEnd
  @finish:
  mov esi, ecx        //����������
  mov ecx, [esp+$0C]
  ret                 //������� � OnAnimationEnd
end;


function CheckGrenadeExplosionByHit(grenade:pointer; SHit:pSHit):boolean;stdcall;
//������� true, ���� �� ����������� ���� ����� ������ ����������
var
  sect:PChar;
begin
  sect:=GetSection(grenade);
  result:=false;
  if game_ini_line_exist(sect, 'help_explosive_info') and game_ini_r_bool(sect, 'help_explosive_info') then begin
    log('Hit type: '+inttostr(SHit.hit_type));
    log('Hit power: '+ floattostr(SHit.power));
    log('Hit impulse: '+ floattostr(SHit.impulse));
    log('Treshold: '+floattostr(CGrenade__GetDetonationTresholdHit(grenade)));
  end;

  if game_ini_line_exist(sect, 'explosion_on_hit') and game_ini_r_bool(sect, 'explosion_on_hit') then begin
    if CGrenade__GetDetonationTresholdHit(grenade)<SHit.power then begin
      if (not CMissile__Useful(grenade)) or (not game_ini_line_exist(sect, 'explosive_while_not_activated')) or game_ini_r_bool(sect, 'explosive_while_not_activated') then begin
        if game_ini_line_exist(sect, 'explosion_hit_types') then begin
          if pos(inttostr(SHit.hit_type), game_ini_read_string(sect, 'explosion_hit_types'))<>0 then result:=true;
        end else begin
          if SHit.hit_type=EHitType__eHitTypeExplosion then result:=true;
        end;
      end;
    end;
  end;

end;


procedure CGrenade__OnHit_CanExplode_Patch();stdcall;
asm
  pushad
    mov eax, 0
    cmp edi, 0 //���� ����� ����������� ��������� �� ��� ������� - ���������� �� �����
    je @nohit
    push edi
    push esi
    call CheckGrenadeExplosionByHit
    @nohit:
    cmp eax, 1
  popad
  ret
end;

procedure ResetActivationHoldState(); stdcall;
begin
  _activate_key_state.IsActive:=false;
end;


///////////////////////////////////////////////////////
//������ ��������� ����� �� ������
function NeedDrawGrenMark(grenade:pointer):boolean; stdcall;
begin
  if (GetCurrentDifficulty()>=gd_veteran) or (CMissile__GetDestroyTime(grenade)=CMISSILE_NOT_ACTIVATED) then
    result:=false
  else
    result:=true;
end;

procedure NeedDrawGrenMark_Patch(); stdcall;
asm
  call eax
  cmp ax, di
  je @finish
  pushad
  push esi
  call NeedDrawGrenMark
  cmp al, 0
  popad
  @finish:
end;

procedure SetForcedQuickthrow(status:boolean);
begin
  _quick_throw_forced:=status;
end;

function GetForcedQuickthrow():boolean;
begin
  result:=_quick_throw_forced;
end;


function CanChangeGrenadeNow(current_grenade:pointer; next_grenade:pointer):boolean; stdcall;
var
  state:cardinal;
begin
  state:=GetCurrentState(current_grenade);

  //����������, ����� ���� ���������� ������� ����� � ����� �� ������
  if (state=EHudStates__eShowing) or (state=EMissileStates__eThrowStart) or (state=EMissileStates__eReady) or (state=EMissileStates__eThrow) or (state=EMissileStates__eThrowEnd) then begin
    result:=false;
    exit;
  end;


  result:=true;
  if (GetOwner(current_grenade)<>GetActor()) and (GetActor()<>nil) then exit;

  ResetChangedGrenade();
  if (state = EHudStates__eHidden) then exit;

  if (state <> EHudStates__eHiding) then begin
    //���� ������ ����� ��������...
    virtual_CHudItem_SwitchState(current_grenade, EHudStates__eHiding);
  end;
  SetChangedGrenade(current_grenade);
  result:=false;
end;

procedure CGrenade__Action_changetype_Patch; stdcall;
asm
  mov ecx,[ebp+$8C] //orig

  pushad
    push esi
    push ebp
    call CanChangeGrenadeNow
    cmp al, 0
  popad

  je @not_change
  ret


  //return fron CALLER proc
  @not_change:
  pop edi //ret addr
  
  pop edi
  pop esi
  pop ebp
  mov al, 01
  pop ebx
  add esp, $0c
  ret 8
end;

function IsGrenadeDeactivated(CGrenade:pointer):boolean; stdcall;
begin
  result:=CMissile__GetDestroyTime(CGrenade)=CMISSILE_NOT_ACTIVATED;
end;

function virtual_CGrenade_DropGrenade(CGrenade:pointer):boolean; stdcall;
asm
  pushad
  mov ecx, [CGrenade]
  mov edx, [eax]
  mov eax, [edx+$150]
  call eax
  mov @result, al
  popad
end;

function NeedSkipExplodeParticle():boolean; stdcall;
begin
  // ��� �������� ���������� �������� �������, ���� ��� ����� ��������� � ������� ������������������
  result:=false;
end;

procedure CExplosive__Explode_Patch(); stdcall;
asm
  xor eax, eax
  cmp [esi+$c8], eax

  pushad
  call NeedSkipExplodeParticle
  test al, al
  popad
  je @finish
  xor ebp, ebp
  pop eax //ret addr
  mov eax, xrgame_addr
  add eax, $301a28
  jmp eax 


  @finish:
end;

procedure CExplosive__OnEvent_Patch(); stdcall;
asm
  // if m_explosion_flags.test(flExploding) then return
  
  mov al, [ecx+$8c] //m_explosion_flags
  test al, 1 //flExploding
  jne @finish

  //original
  cmp word ptr [esp+$24],$18
  @finish:
end;

////////////////////////////////////////////////////////
function Init():boolean;
var
  jump_addr, buf:cardinal;
begin
  result:=false;
  ResetActivationHoldState();
  SetForcedQuickthrow(false);
  
  jump_addr:=xrGame_addr+$2C6C76;
  if not WriteJump(jump_addr, cardinal(@CMissile__Load_Patch), 6, true) then exit;
  jump_addr:=xrGame_addr+$2C75A5;
  if not WriteJump(jump_addr, cardinal(@CMissile__State_anm_Patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2C7624;
  if not WriteJump(jump_addr, cardinal(@CMissile__State_anm_Patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2C76AF;
  if not WriteJump(jump_addr, cardinal(@CMissile__State_anm_Patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2C773B;
  if not WriteJump(jump_addr, cardinal(@CMissile__State_anm_Patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2C6734;
  if not WriteJump(jump_addr, cardinal(@CGrenade__SendHiddenItem_Patch), 11, true) then exit;
  jump_addr:=xrGame_addr+$2C7FA1;
  if not WriteJump(jump_addr, cardinal(@CMissile__OnAnimationEnd_Patch), 6, true) then exit;
  jump_addr:=xrGame_addr+$2C6FD0;
  if not WriteJump(jump_addr, cardinal(@CMissile__OnMotionMark_Patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2C7500;
  if not WriteJump(jump_addr, cardinal(@CMissile__OnActiveItem_Patch), 5, true) then exit;
  jump_addr:=xrGame_addr+$2C6919;
  if not WriteJump(jump_addr, cardinal(@CMissile__PutNextToSlot_SameItemFound_Patch), 8, true) then exit;
  jump_addr:=xrGame_addr+$2C6958;
  if not WriteJump(jump_addr, cardinal(@CMissile__PutNextToSlot_NoItem_Patch), 12, true) then exit;
  jump_addr:=xrGame_addr+$2C6F95;
  if not WriteJump(jump_addr, cardinal(@CMissile__shedule_update_Patch), 5) then exit;
  jump_addr:=xrGame_addr+$2C719B;
  if not WriteJump(jump_addr, cardinal(@CMissile__ExitContactCallback_Patch), 5) then exit;
  jump_addr:=xrGame_addr+$2C5B5C;
  if not WriteJump(jump_addr, cardinal(@CGrenade__OnHit_CanExplode_Patch), 31, true) then exit;

  //CMissile::Throw - xrgame.dll+2c8cb0 

  jump_addr:=xrGame_addr+$267BBE;
  if not WriteJump(jump_addr, cardinal(@NeedDrawGrenMark_Patch), 5, true) then exit;

  //[bug] ��� - ��� ����� ���� ����� ��� ����� ��������
  jump_addr:=xrGame_addr+$2c658f;
  if not WriteJump(jump_addr, cardinal(@CGrenade__Action_changetype_Patch), 6, true) then exit;

  //� CExplosive::Explode �� ��� ��������� ������� ����� ��������� ������� 
  jump_addr:=xrGame_addr+$3019cc;
  if not WriteJump(jump_addr, cardinal(@CExplosive__Explode_Patch), 8, true) then exit;

  //[bug] ��� - � CExplosive::OnEvent ��������� �������� �� ��, ��� �� ��� �� ����������
  jump_addr:=xrGame_addr+$300173;
  if not WriteJump(jump_addr, cardinal(@CExplosive__OnEvent_Patch), 6, true) then exit;

  result:=true;

end;

// CExplosive::Explode - xrgame.dll+301880
// CExplosive::StartLight - xrgame.dll+300600

end.
