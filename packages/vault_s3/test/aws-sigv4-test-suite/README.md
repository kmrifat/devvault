# AWS SigV4 test suite

Copied from [awslabs/aws-c-auth](https://github.com/awslabs/aws-c-auth),
`tests/aws-signing-test-suite/v4/`, at commit
`8915397af98127855562b07013707e25a4cc54fa` (Apache-2.0; see `LICENSE` and
`NOTICE`). Only the header-signing files are kept: `context.json`,
`request.txt` and `header-*`. The `query-*` presigned-URL files aren't
copied, because DevVault doesn't presign.

`../sigv4_suite_test.dart` runs every case through `SigV4Signer`.
