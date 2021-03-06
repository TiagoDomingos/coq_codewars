DECLARE PLUGIN "coq_cw_plugin"

open Stdarg

VERNAC COMMAND EXTEND CWAssertType CLASSIFIED AS QUERY
| [ "CWAssert" string_opt(msg) ref(r) ":" constr(ty)] -> [ 
        Coq_cw.test_type ?msg r ty
    ]
END

VERNAC COMMAND EXTEND CWAssertAssumptions CLASSIFIED AS QUERY
| [ "CWAssert" string_opt(msg) ref(e) "Assumes" ref_list(axioms)] -> [ 
        Coq_cw.test_axioms ?msg e axioms
    ]
END

VERNAC COMMAND EXTEND CWStopOnFailure CLASSIFIED AS SIDEFF
| [ "CWStopOnFailure" int(flag)] -> [
        Coq_cw.stop_on_failure flag
    ]
END

VERNAC COMMAND EXTEND CWGroup CLASSIFIED AS SIDEFF
| [ "CWGroup" string(msg)] -> [ 
        Coq_cw.begin_group "DESCRIBE" msg
    ]
END

VERNAC COMMAND EXTEND CWEndGroup CLASSIFIED AS SIDEFF
| [ "CWEndGroup"] -> [
        Coq_cw.end_group "DESCRIBE"
    ]
END

VERNAC COMMAND EXTEND CWTest CLASSIFIED AS SIDEFF
| [ "CWTest" string(msg)] -> [ 
        Coq_cw.begin_group "IT" msg
    ]
END

VERNAC COMMAND EXTEND CWEndTest CLASSIFIED AS SIDEFF
| [ "CWEndTest"] -> [
        Coq_cw.end_group "IT"
    ]
END

VERNAC COMMAND EXTEND CWFileSize CLASSIFIED AS QUERY
| [ "CWFile" string_opt(fname) "Size" "<" int(size)] -> [ 
        Coq_cw.test_file_size ?fname size
    ]
END

VERNAC COMMAND EXTEND CWFileMatch CLASSIFIED AS QUERY
| [ "CWFile" string_opt(fname) "Matches" string(regex)] -> [ 
        Coq_cw.test_file_regex ?fname true regex
    ]
END

VERNAC COMMAND EXTEND CWFileNegMatch CLASSIFIED AS QUERY
| [ "CWFile" string_opt(fname) "Does" "Not" "Match" string(regex)] -> [ 
        Coq_cw.test_file_regex ?fname false regex
    ]
END

VERNAC COMMAND EXTEND CWCompileAndRun CLASSIFIED AS SIDEFF
| [ "CWCompileAndRun" string_list(files) "Options" string_opt(options) "Driver" string(driver) ] -> [
        Coq_cw.compile_and_run files ?options driver
    ]
END
