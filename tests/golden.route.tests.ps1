# =============================================================================
#  tests/golden.route.tests.ps1  —  ルート分類 の期待入出力テーブル（層2 有効）
#
#  対象ロジック（src/utils.ps1 Resolve-Route。呼び出し元は com-handler.ps1 Watch-RunningPresentation）:
#    Resolve-Route([string]$Path, [string]$Method) -> pscustomobject
#      .Kind  : 'auth'|'status'|'elapsed'|'slide-state'|'lock-on'|'lock-steal'|'lock-off'|'slide'|'stop'|'other'
#      .Cmd   : string（Kind='slide' のときのみ有効）
#      .Valid : bool  （Kind='slide' のときのみ有効。valid 集合: next, prev, first, last, blackout, whiteout）
#
#  現状仕様として固定する挙動（このファイル内の期待表 [F]）:
#    - /status, /elapsed, /slide/state はメソッド非依存（POST でも同じ Kind）
#    - /slide/state は /slide/* より先に判定される
#    - GET /auth は 'other'（未認証アクセスは認証ガードで AuthView を返す。Resolve-Route の分類値は維持）
# =============================================================================

. (Resolve-SrcFunction -Path "$PSScriptRoot/../src/utils.ps1" -Name 'Resolve-Route')

$r = Resolve-Route '/status' 'GET';       Assert-Equal 'status'      $r.Kind  '[F] /status GET'
$r = Resolve-Route '/status' 'POST';      Assert-Equal 'status'      $r.Kind  '[F] /status POST (method 非依存)'
$r = Resolve-Route '/elapsed' 'GET';      Assert-Equal 'elapsed'     $r.Kind  '[F] /elapsed GET'
$r = Resolve-Route '/slide/state' 'GET';  Assert-Equal 'slide-state' $r.Kind  '[F] /slide/state GET'
$r = Resolve-Route '/slide/state' 'POST'; Assert-Equal 'slide-state' $r.Kind  '[F] /slide/state POST (slide より先)'

$r = Resolve-Route '/lock/on' 'POST';     Assert-Equal 'lock-on'     $r.Kind  '[F] /lock/on POST'
$r = Resolve-Route '/lock/steal' 'POST';  Assert-Equal 'lock-steal'  $r.Kind  '[F] /lock/steal POST'
$r = Resolve-Route '/lock/off' 'POST';    Assert-Equal 'lock-off'    $r.Kind  '[F] /lock/off POST'
$r = Resolve-Route '/lock/on' 'GET';      Assert-Equal 'other'       $r.Kind  '[F] /lock/on GET'

$r = Resolve-Route '/slide/next' 'POST';  Assert-Equal 'slide' $r.Kind  '[F] /slide/next kind'
										  Assert-Equal 'next'  $r.Cmd   '[F] /slide/next cmd'
										  Assert-Equal $true   $r.Valid '[F] /slide/next valid'
$r = Resolve-Route '/slide/zzz' 'POST';   Assert-Equal 'slide' $r.Kind  '[F] /slide/zzz kind'
										  Assert-Equal 'zzz'   $r.Cmd   '[F] /slide/zzz cmd'
										  Assert-Equal $false  $r.Valid '[F] /slide/zzz valid'
$r = Resolve-Route '/slide/' 'POST';      Assert-Equal 'slide' $r.Kind  '[F] /slide/ kind'
										  Assert-Equal ''      $r.Cmd   '[F] /slide/ cmd (空)'
										  Assert-Equal $false  $r.Valid '[F] /slide/ valid'
$r = Resolve-Route '/slide/next' 'GET';   Assert-Equal 'other' $r.Kind  '[F] /slide/next GET (POST 以外は slide 対象外)'

$r = Resolve-Route '/auth' 'POST';        Assert-Equal 'auth'  $r.Kind  '[F] /auth POST'
$r = Resolve-Route '/auth' 'GET';         Assert-Equal 'other' $r.Kind  '[F] /auth GET (認証ガードでAuthView / route分類はother維持)'
$r = Resolve-Route '/stop' 'POST';        Assert-Equal 'stop'  $r.Kind  '[F] /stop POST'
$r = Resolve-Route '/stop' 'GET';         Assert-Equal 'other' $r.Kind  '[F] /stop GET'
$r = Resolve-Route '/unknown' 'GET';      Assert-Equal 'other' $r.Kind  '[F] /unknown GET'
