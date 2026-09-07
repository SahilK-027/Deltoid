/// Which half of a long job is running, so the screen can say something more
/// useful than "working".
///
/// One vocabulary covering three operations. An export, a restore and a first
/// pull present identically to the user — thousands of rows being processed
/// while the application must not appear to have stopped responding — so they
/// report through a single type and a single sheet rather than through three
/// that diverge ([SYNC.md § 16](SYNC.md#16-still-to-decide)).
enum JobPhase {
  /// Rows coming off this device's disk.
  reading,

  /// One opaque `jsonEncode` of everything read.
  encoding,

  /// Rows going onto this device's disk.
  writing,

  /// A file being parsed, before a row of it has landed.
  decoding,

  /// Making room for a restore.
  clearing,

  /// Rows coming down from the account.
  ///
  /// Distinct from [reading] because it is the one phase that depends on a
  /// network: the same volume as a restore, down a slower path, and the
  /// sentence on screen has to say so or a stalled bar reads as a hang.
  pulling,
}

/// A step of a long job: what it is doing, what on, and how far through.
///
/// [fraction] is null while a phase genuinely cannot say — a `jsonEncode` of a
/// hundred thousand rows is one opaque call. A bar that sits still is honest;
/// one that invents a percentage and then jumps is not.
typedef JobStep = ({
  JobPhase phase,
  String detail,
  int rows,
  double? fraction,
});

typedef ProgressReport = void Function(JobStep step);
