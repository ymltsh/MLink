/// 将一个参数作为远端 POSIX shell 的单个字面值传入。
String quotePosix(String value) {
  if (value.contains('\x00')) throw ArgumentError('参数不能包含 NUL');
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}
