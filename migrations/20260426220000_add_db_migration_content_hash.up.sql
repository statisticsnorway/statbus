-- Add a content_hash column to db.migration so the migrate runner can
-- detect in-place edits to already-applied migration files (the rc63
-- "fix-by-editing" pattern that violated migration immutability and
-- left releases internally inconsistent).
--
-- Lifecycle (per plan section R, commit 2/4):
-- - Column added; backfilled in this same migration with hardcoded
--   sha256 hashes for every prior migration file (one UPDATE per
--   version, generated at authoring time from the on-disk bytes).
--   No silent NULL window, no reliance on filesystem state at
--   apply-time.
-- - The runner stamps content_hash on every subsequent INSERT
--   (apply, redo) so new rows always carry a hash.
-- - On every `./sb migrate up`, before the pending-only filter, the
--   runner compares the live file's sha256 to the stored hash for
--   each row. Mismatch fires an error with two arms:
--     * Migration version is in a released tag → immutability
--       violation (hard fail; create a new migration instead).
--     * Migration version is unreleased WIP → "Run: ./sb migrate
--       redo <version>" (recoverable).
-- - NOT NULL constraint is applied at the end of this migration so
--   silent NULL is structurally impossible going forward.
--
-- The companion `./sb migrate redo` primitive (introduced alongside
-- this column) re-runs down + up for a WIP-edited migration, deletes
-- the tracking row, and re-inserts so the content_hash refreshes.

BEGIN;

ALTER TABLE db.migration ADD COLUMN content_hash text;

COMMENT ON COLUMN db.migration.content_hash IS
    'sha256 of the migration file bytes at apply time. Backfilled at '
    'column-add via hardcoded UPDATE statements in this migration; '
    'stamped by the runner on every subsequent INSERT (apply, redo). '
    'Mismatch detection fires before the pending-only filter on every '
    '`./sb migrate up` — a stored hash that no longer matches the live '
    'file is either an immutability violation (released migration '
    'edited) or a WIP edit recoverable via `./sb migrate redo <version>`. '
    'NOT NULL: silent NULL is structurally impossible. '
    'Per plan-rc.66 section R.';

-- Hardcoded backfill: one UPDATE per known prior migration. Hashes
-- generated at authoring time from the on-disk file bytes via
-- `sha256sum migrations/<version>_*.up.{sql,psql}`. Sorted by version
-- for readability. Skips the version number of THIS migration —
-- 20260426220000's tracking row is INSERTed by the runner with its
-- own content_hash stamped at apply time (not here).

UPDATE db.migration SET content_hash = '8e22e97fff1b509a93b46032bc5c407a29721ca8c75f7a4cd83167f28c108b86' WHERE version = 20240102000000;
UPDATE db.migration SET content_hash = '95fc6f3e145892e574b28ba91e872526630d2a51d5eb7170ce1d8dd9ac4763b0' WHERE version = 20240102100000;
UPDATE db.migration SET content_hash = 'c1022b189aabd1d4f45b239cea8de84a38782b8784828e4c5260ee324657ced5' WHERE version = 20240103000000;
UPDATE db.migration SET content_hash = '2c18f17398751da2340c14b9ebc190bb978170ba56d62b71ab4819ea3e3d0907' WHERE version = 20240104000000;
UPDATE db.migration SET content_hash = '31e0154534414924a095c9c9f2ae4ae7f118f3fd116ce9795209d487dfde5840' WHERE version = 20240105000000;
UPDATE db.migration SET content_hash = '9c6815d8931c74a27a8aaa93ffd8ef10cee3181159d40646c6b61866be621bdc' WHERE version = 20240106000000;
UPDATE db.migration SET content_hash = '6fdaf98664dadfbc07b851a663741acf427faf8176e58cd23c1eabef7c700139' WHERE version = 20240107000000;
UPDATE db.migration SET content_hash = 'cc3b8ffb2945192c20fc6e1ccb0117418d98d7c4765499cacc5c144d01cf4127' WHERE version = 20240108000000;
UPDATE db.migration SET content_hash = '21c638017f477aa04bada702d2d295a58d769470c89a3ca45771b7c736dd6646' WHERE version = 20240109000000;
UPDATE db.migration SET content_hash = 'b8650a05faac6d069e66871cf8f5569eb535f6d5a03a910d030e97ae253b5139' WHERE version = 20240110000000;
UPDATE db.migration SET content_hash = 'cfbc5fb7e51ed1908042bd0771509e15e9a791a55c51b6c75a6236ef5af1d15e' WHERE version = 20240111000000;
UPDATE db.migration SET content_hash = 'd0bf9364195d4dfc5591da3a1ec63ee47a09bfb98de8e10812b8a770065e1428' WHERE version = 20240111120000;
UPDATE db.migration SET content_hash = 'b136e301a621fb10faa725cb263851eeb8db12f5a66aebd48a0ed9ca478dbeb4' WHERE version = 20240112000000;
UPDATE db.migration SET content_hash = '239c873691d72bb9fd8e44f18c61c3954d060d225c16f400aedab2a09904b74c' WHERE version = 20240113000000;
UPDATE db.migration SET content_hash = '22efaec5099b7ec3ccd32ae300344b8fa59a967d2ce45cfe496a8a57ba24ce38' WHERE version = 20240115000000;
UPDATE db.migration SET content_hash = 'b93f6bdf215a3bed53bbaefa72f4ceeb7dd6a206c80e80e214031fab7206d854' WHERE version = 20240116000000;
UPDATE db.migration SET content_hash = '1904a2d3f62926c7c7ce5ba6f7d56134668aaf36aba23887511c1a295d1c120e' WHERE version = 20240117000000;
UPDATE db.migration SET content_hash = 'ad22b0afbb7a4fadb9523dcfb67758657f1c3b742f321cdd6310f99fedc81840' WHERE version = 20240119000000;
UPDATE db.migration SET content_hash = 'fba3ad93214f6de7e60ac1743c15155867ea13ff5e5678ebda3e1a3f1f17a790' WHERE version = 20240121000000;
UPDATE db.migration SET content_hash = '7909546f500e457c998fc4dd7df8b91d6015ed04ac5b27a225874b447fb2fa12' WHERE version = 20240122000000;
UPDATE db.migration SET content_hash = 'f1a4d29c3487e8b9c65ff1b627c9a26f3402910bbce9ca743a8da6033f61e0ea' WHERE version = 20240123000000;
UPDATE db.migration SET content_hash = '0a5eb795c852f70181cab57d990486328afa0cfdc6af425840cc3dba13459aaf' WHERE version = 20240123100000;
UPDATE db.migration SET content_hash = 'acd62bd9f017d0f511c08da369787b1ac9f042534171a67338039d889040044c' WHERE version = 20240124000000;
UPDATE db.migration SET content_hash = '82f17e4eb45c9aa49fffcdf266c820f87081220ea762e815246f7e28efb3049f' WHERE version = 20240125000000;
UPDATE db.migration SET content_hash = 'a79169993313907029b177304020aa4386a9f7c980f70b1370b62cf67a75e707' WHERE version = 20240127000000;
UPDATE db.migration SET content_hash = '7e6853ae14eb2a1ababc4707703845432a737c7de48535b64854e92da015894f' WHERE version = 20240127120000;
UPDATE db.migration SET content_hash = '857399e9b63041291f5e1d11876407a3e7540092aa4085309fc113b9fe1369ec' WHERE version = 20240127130000;
UPDATE db.migration SET content_hash = '4b07170c4bc35484e6e5ada447f8543f37d2295ce35a43d282fc09eb2898c069' WHERE version = 20240128000000;
UPDATE db.migration SET content_hash = '641a299d9cbd56ac76399466cb288baa334611128f1f7eb46e91f4ab220f668a' WHERE version = 20240129000000;
UPDATE db.migration SET content_hash = 'fd7494f51947f57ccd669f13048e57d16f0ff9ce7d74d994dad22f4375d6eb9b' WHERE version = 20240130000000;
UPDATE db.migration SET content_hash = 'c05a6af7c81168aceb18d84ada7bd0111ab359a67c5400ccd14c8363a071948a' WHERE version = 20240130100000;
UPDATE db.migration SET content_hash = '601aa01c70399b3bcc826be2f537b30cc0302426c28fc96a823e0f5620bba94d' WHERE version = 20240131000000;
UPDATE db.migration SET content_hash = 'a6a5c513ed530eabcbf035cbcb9bd9742c7866ab77e2b5d9aad19a07dd916617' WHERE version = 20240201000000;
UPDATE db.migration SET content_hash = '31a5e02d4bb0777107e6f8d601522e27e8a56574691c6eb01dcddcf808a5ca7a' WHERE version = 20240203000000;
UPDATE db.migration SET content_hash = '98921bdb115262914d194ea09e120e8b4553ed5be499d7872784c31a8e824a3f' WHERE version = 20240204000000;
UPDATE db.migration SET content_hash = '30b8354b2278d3e783908e43cd68292c432737fec23e075f5ffee237f8ff3cec' WHERE version = 20240205000000;
UPDATE db.migration SET content_hash = 'd12b28486caa6e52f0ab0d29238c668feffbb491f043fe00101e0947f9bd275d' WHERE version = 20240206000000;
UPDATE db.migration SET content_hash = '0e8fa764de75236d3586c63a4ab023309519bbb30be8447319c4267b37d75fb3' WHERE version = 20240206120000;
UPDATE db.migration SET content_hash = 'c1d1442ed3b1dc6434c5dea3a8a1df3d5d90d7f6a2df629830351e2bd484933f' WHERE version = 20240206180000;
UPDATE db.migration SET content_hash = '7b684a9501ee51df2f9353f1351472308420c6c09435c1ab0d9bb31c39a3c954' WHERE version = 20240207000000;
UPDATE db.migration SET content_hash = '464d0d7c370e827b8ac863c08350cadd4bb653232399d310fc5a226c94fd659f' WHERE version = 20240208000000;
UPDATE db.migration SET content_hash = 'd2e223ae84febb99dd8804b6d9a40d228d0782bccb0584f380ace77e646b21ba' WHERE version = 20240209000000;
UPDATE db.migration SET content_hash = 'cbe2d4c0ba0da6e05b2532e893a58e46a11b14b27efb581945967bdbe09c02f3' WHERE version = 20240210000000;
UPDATE db.migration SET content_hash = 'f7f659cb3a1e43cb360308acd5fe628250cdbb1fb28d814d3fe76c623e637429' WHERE version = 20240211000000;
UPDATE db.migration SET content_hash = 'b0e3076a6becc87098f1a92997ee9a24620b1d3db9ec3311b3d48a47e0d17805' WHERE version = 20240212000000;
UPDATE db.migration SET content_hash = '907a8337d72c1cad9912633ec8701d9a48db2188e403a7fb6e100f5ecba3b856' WHERE version = 20240213000000;
UPDATE db.migration SET content_hash = '5842cb193ec2a990ef7b6c148d5d0f74a1cda41d100caad4390df01baa44ec79' WHERE version = 20240214000000;
UPDATE db.migration SET content_hash = '1f539b4326c63b8cd8687a0a91c9f966706e483b630d9c3b8f33c6797371e8a5' WHERE version = 20240215000000;
UPDATE db.migration SET content_hash = '4e9650cc761a2fb1e97d9841be6f857a27a5e8bb3d083acd91beee1ac913a80c' WHERE version = 20240216000000;
UPDATE db.migration SET content_hash = 'b102b1f47546a1ebb63240583d4c440b31a6f4b0330b90f760b53bb62cb51e18' WHERE version = 20240217000000;
UPDATE db.migration SET content_hash = '350c9a7753a678b62e8c34ba0a5bab92b92bf5c70b6dd36b6467e7dc60c7a9f1' WHERE version = 20240218000000;
UPDATE db.migration SET content_hash = 'ed3e5db6ca74ae2dd724666006aaa2792bd2334d35920ab592c4828287e347d9' WHERE version = 20240219000000;
UPDATE db.migration SET content_hash = 'ae1dbc3f76847153e2051f50cbc6bdc4630a1cb9116db925afc8979394e5ca21' WHERE version = 20240220000000;
UPDATE db.migration SET content_hash = 'ec49f7870155dfea5333b700669fa4daec916f190c5de6ce2c73b52da96ac548' WHERE version = 20240221000000;
UPDATE db.migration SET content_hash = '45177c486632ec5be65282082aa704fb75f6b47dab9067385025b17a681ff5a7' WHERE version = 20240222000000;
UPDATE db.migration SET content_hash = 'b8cdc3721c817c8f9c73a256ba62c10425348b48d63f3732e853f00cf546614c' WHERE version = 20240223000000;
UPDATE db.migration SET content_hash = 'd1883f3c963b0232a552a82e0916b0299e581a9453732d32c1b2ff2df48fc09f' WHERE version = 20240224000000;
UPDATE db.migration SET content_hash = 'd5e9f8501e3e968eb5011098faed7b48ba47892e3c7aff7530da566d0e373a5d' WHERE version = 20240225000000;
UPDATE db.migration SET content_hash = '1eef37fc4a93e1251d02a016ae973068c5bec052f8a88c47659546a7cae66ff6' WHERE version = 20240226000000;
UPDATE db.migration SET content_hash = 'e747433262367d09206b855529f2131c7a7127ffcc3c7599f444861a3c5f2ba5' WHERE version = 20240227000000;
UPDATE db.migration SET content_hash = '933fb1ab19e260ecc176be85dc96d3b48c08124139611546f7c74a5514580406' WHERE version = 20240227120000;
UPDATE db.migration SET content_hash = '450e195e27b81a0b5db9be3927cbb41693f1c1a034cee60d5b1863ce8fe167af' WHERE version = 20240228000000;
UPDATE db.migration SET content_hash = '848825bc1a2e2f2c24c83d1d70cd19c0f3d6b7953c402036e3ef7cdae088b23f' WHERE version = 20240228000001;
UPDATE db.migration SET content_hash = '33b59b71075df24855b086eebf72f10e1a974db145382c2d4ae423802e2e97a7' WHERE version = 20240229000000;
UPDATE db.migration SET content_hash = 'f02c5806fe65d1a1d5b554eb54b5fa3b2f320ff8dbcadb173634bd8fc2b9c549' WHERE version = 20240301000000;
UPDATE db.migration SET content_hash = 'a04d8b4d340800b66c0ced23e65a29cfff67505f0105ef9bf2e07b5ad66d5b42' WHERE version = 20240302000000;
UPDATE db.migration SET content_hash = '90c52e3801c71d63251d7243aabbfbb8c43519b32c9c08175a8bdea06fce0c4f' WHERE version = 20240303000000;
UPDATE db.migration SET content_hash = '842d3fa8ab8d1d784ee4d1919bc4b8aa88e8d853f02ea6c801c52c553b76b831' WHERE version = 20240305000000;
UPDATE db.migration SET content_hash = 'b66694ad33cc35afc058fd3c59485a45607e74753d40e3531b375cc4c18eeb73' WHERE version = 20240306000000;
UPDATE db.migration SET content_hash = '24fad30bc0ccc741f6504efe9528a0383f56dad1ad77d5806414177489e19851' WHERE version = 20240307000000;
UPDATE db.migration SET content_hash = 'a7196a743c6eca7a06612d99aa324108d9e8baac82487e658c2557389b90fa54' WHERE version = 20240308000000;
UPDATE db.migration SET content_hash = 'd8f1e922421542a752d2c23186db22f74cffa1c4fc64815983132f913e6d6748' WHERE version = 20240310000000;
UPDATE db.migration SET content_hash = '7a25deafebb4be5e16a97806782058a638d054bc350222453c6d1a4b85d618c1' WHERE version = 20240311000000;
UPDATE db.migration SET content_hash = '19dfade5dd3d7b52dab689885aa11df27d8def9e31bcb5ae267c0e9e978f0e1c' WHERE version = 20240312000000;
UPDATE db.migration SET content_hash = '44e17796ecab45f5f560041bdba4e753e6f45840548c92b942ddcf9560acaec6' WHERE version = 20240313000000;
UPDATE db.migration SET content_hash = 'bb784ed39b638c512957160b88e5f940d3de98f22372c41488d2b1253630c62e' WHERE version = 20240314000000;
UPDATE db.migration SET content_hash = '3415d462368a3a8cb9ce8d92771b6e12f67d782ebe8693fe075ca7bcb8cbb664' WHERE version = 20240315000000;
UPDATE db.migration SET content_hash = 'e7aa1b009f19be59929937b7132d3e84f8f710a900d0570b162d087e6b36dc33' WHERE version = 20240316000000;
UPDATE db.migration SET content_hash = '5f1b9efd6c023bb695da4e2d6d8a045c46248ccd18c651c0063bb075faea4c72' WHERE version = 20240317000000;
UPDATE db.migration SET content_hash = 'f11eff39426343f055729ee0d0464a210db90c2acee2a31e20b9ab5572429902' WHERE version = 20240318000000;
UPDATE db.migration SET content_hash = 'e9b3c8186e01fa758802b4707b5e14960ea78b113b78719b1e3aa8da0534fbb9' WHERE version = 20240319000000;
UPDATE db.migration SET content_hash = 'ca8fe8527cb84ee1a4e9a5c16d82f326dcb94d8d0cc9400ee3fcb29bcbd6dc55' WHERE version = 20240320000000;
UPDATE db.migration SET content_hash = 'e409c64c4674664cb72c9c57119888ca884a4497a075c4db33a26c3c07d846ef' WHERE version = 20240321000000;
UPDATE db.migration SET content_hash = '26a59c775b3dea79697bf5bf6a2babd7690dcab9feb62e1149e1b9d84dad1296' WHERE version = 20240322000000;
UPDATE db.migration SET content_hash = '8f7e9428396b1b7bf43542d8bf7d80c1c31da1a1ed96dfd5323b7bb1e4121653' WHERE version = 20240323000000;
UPDATE db.migration SET content_hash = '016240f0348f5f505b60063271768c10d9b5ad0b6e161bacc90aca8d54ca1d93' WHERE version = 20240324000000;
UPDATE db.migration SET content_hash = '1e567bb622286ed754f35e01c769e77d2357a6b909c30eb838d851261e5b1578' WHERE version = 20240325000000;
UPDATE db.migration SET content_hash = 'dacab1901459a6ee88a9eb406fa07f168a5147a016f87bd822c335ab2884e76f' WHERE version = 20240326000000;
UPDATE db.migration SET content_hash = 'ed3c5346cae73a27e544bbec81f0baa9f92a13e4ac030762b988e70e3e17c5ae' WHERE version = 20240327000000;
UPDATE db.migration SET content_hash = '3e524cef8c5e9d222ec223d954e74402f76f8573a197f3d2fb9f16745185a454' WHERE version = 20240328000000;
UPDATE db.migration SET content_hash = '208534f01d7838fd9f26a718ae0c1c543192d9c26fe8ad8d754e66c0d65c1024' WHERE version = 20240329000000;
UPDATE db.migration SET content_hash = '38040779e3fdde3e4a5cf2ddc258cebffebe3eabcc9a059dd8084759f2efc996' WHERE version = 20240330000000;
UPDATE db.migration SET content_hash = '37a9e2273908b68b54302e01e434d14a74d94d728b618b9ee029f15b949d8a47' WHERE version = 20240331000000;
UPDATE db.migration SET content_hash = 'e86925579fba135a138caf8c56a9c80fb045b3118560bc94dee314f0119bb2db' WHERE version = 20240401000000;
UPDATE db.migration SET content_hash = '85021590896032967ec94b76e2188e958e7049777e5be6fec5ec8284c56bfa89' WHERE version = 20240402000000;
UPDATE db.migration SET content_hash = '1cef8a11488828c93d33bb093d6015e62af70c420fb7c896b5554dd5ba76b3ba' WHERE version = 20240403000000;
UPDATE db.migration SET content_hash = '05bce6b709eca706b9d97abaa21578b6fe443962c84ab12b55af6ff308d38ea9' WHERE version = 20240404000000;
UPDATE db.migration SET content_hash = '0d65d9bdf46122fb7d7cd259526a867b19cce0097a1a220a9223ebaecef39381' WHERE version = 20240405000000;
UPDATE db.migration SET content_hash = 'c62b8492922dec85a8c70f537206f70c892d51f21c66fb03fd75ab97d9fd68f6' WHERE version = 20240406000000;
UPDATE db.migration SET content_hash = 'f375e95610286779d2b38a407571ec03ae1773058e5b7a38a040e2af0526d246' WHERE version = 20240407000000;
UPDATE db.migration SET content_hash = '856e0d8a4087b5ad7bb02f0dff33e5c1cc250f02d781755fb675f675f63c9751' WHERE version = 20240407120000;
UPDATE db.migration SET content_hash = 'dc601b925e0654b920a812508478cf0c9e267daaa82b1a604d796fda65b5edbf' WHERE version = 20240408000000;
UPDATE db.migration SET content_hash = '2bfe6f49290355d741ef024eea9e84c9b1b534ecc39c57282bfdb67956724120' WHERE version = 20240409000000;
UPDATE db.migration SET content_hash = 'f8f21c6c6dda91c0ff5464a3d4bd2852de1a321c2e2dd41e5c1c4bc665ed8d55' WHERE version = 20240410000000;
UPDATE db.migration SET content_hash = '30193f52b821910341d2ec33b4a14287fa0fc24d38791d8008477178c31a11ce' WHERE version = 20240411000000;
UPDATE db.migration SET content_hash = '926645e2702dc2a733e9d4cfb3173ca0d8ba530da2243223e4f2d3b8af47edfa' WHERE version = 20240412000000;
UPDATE db.migration SET content_hash = '51374757566c7df77bb5276c711b7288d88a124071e99eebfddbbf51d379cc57' WHERE version = 20240413000000;
UPDATE db.migration SET content_hash = '94475346885d0b3ffe97c091e0cc4d1f3320728056ab2ed3a979a58c467f3426' WHERE version = 20240416000000;
UPDATE db.migration SET content_hash = '60c4b816d8cd0d9d6379cddd5c78d559728e852ea2367d7610abd329180ccbad' WHERE version = 20240417000000;
UPDATE db.migration SET content_hash = 'b152e43ce79df32f79c064e775368d42b93488df80d3f7d4120cf71ed3e8c533' WHERE version = 20240418000000;
UPDATE db.migration SET content_hash = '1e3d2dc7e6063cc5e086d3da3b64fa08ca8fd76ab1b724c6ac9c58e06c51cf43' WHERE version = 20240419000000;
UPDATE db.migration SET content_hash = 'bfad810e2db2f390035dce448be90e11adf729cbdacb46aaaff5d036af0f1448' WHERE version = 20240420000000;
UPDATE db.migration SET content_hash = '565fadde939feed799843d099b65292275c05517a6cc4aaaa8f54a4c41e09e73' WHERE version = 20240421000000;
UPDATE db.migration SET content_hash = 'eaed1efa40347ca28603e661e32ef01b84e8f17f8de079f66203f8406f670e05' WHERE version = 20240422000000;
UPDATE db.migration SET content_hash = 'e36040a4449fa5dec932e0b2f2eb14b88baa2c6ebea5452adc7c958f3bd634d4' WHERE version = 20240423000000;
UPDATE db.migration SET content_hash = 'fbfa01533c621d813d43669e4a07f9854bc16c0866bdbd7add1108f189610643' WHERE version = 20240424000000;
UPDATE db.migration SET content_hash = 'a49bcfe65bf8b887a039f72a83c3eabb91cfc8af2002f278b998de9f3fd2bcd2' WHERE version = 20240425000000;
UPDATE db.migration SET content_hash = '57ca31046807837751724682d0bc6c0a062575704024a5f3b040b8f51d2c6977' WHERE version = 20240426000000;
UPDATE db.migration SET content_hash = '506d3e0de91dee220de8f43a793f0092b2320351840c46decea28e3ac7a5f500' WHERE version = 20240427000000;
UPDATE db.migration SET content_hash = '29d2c16acda0fea62a3ef70127025b7f6bde6f7ae8397940a51ccfe7d1ec1eb9' WHERE version = 20240428000000;
UPDATE db.migration SET content_hash = 'cc4679916b19ad6717f298fc1d3bc71ce7eae27396a1f2356459688e1641c5a4' WHERE version = 20240531000000;
UPDATE db.migration SET content_hash = '1a0878c46866b8c0c76f6cc0b9cabbfae284067b1e8866fe72b2d0e323fac16a' WHERE version = 20240601000000;
UPDATE db.migration SET content_hash = 'd40ec9d924feae99b73025342514ebb802e437b44f64bdc77f6779b398ce4d90' WHERE version = 20240603000000;
UPDATE db.migration SET content_hash = '12a740f83ebbb6ddc5b47a92cac8215a848cb932c4811a7fe6ab8d95bcd3932e' WHERE version = 20240605000000;
UPDATE db.migration SET content_hash = '0f4a2ca8939e2b9b0a830623feeaa1fdb0b010379c5d8278192a895f404e4ab0' WHERE version = 20240606000000;
UPDATE db.migration SET content_hash = '5fdd628b79e18f1a4767d7b904ced22c5a06e7e24f74d81c145a3c235b2941b6' WHERE version = 20240608000000;
UPDATE db.migration SET content_hash = '8bfeb33af08595000afa5452b15e22a88930fa89db773f82ed97d77f2a302fba' WHERE version = 20240609000000;
UPDATE db.migration SET content_hash = '198a28bcccf2b7cdc03776f5a3da5c9f6040eeb4beb6a1d0bfb374bedc0162ee' WHERE version = 20250123000000;
UPDATE db.migration SET content_hash = '8e3c59864ecffca4df43da418cf8ecb5654d92a750bfa4554b13c979e54c30d2' WHERE version = 20250213100637;
UPDATE db.migration SET content_hash = '517eb0ba14c899b1133ae9713ed3527446f4469c68abd8be634994522bbf80cb' WHERE version = 20250402000000;
UPDATE db.migration SET content_hash = '8cf317f1a48ba19ccce59d086a4fa23b9fff0d9243095185f52bec1190612fdc' WHERE version = 20250422155400;
UPDATE db.migration SET content_hash = '363fc17110f991111dfae0174c94991256e12a98bf3d583b3185a3d3535fd6dc' WHERE version = 20250423000000;
UPDATE db.migration SET content_hash = '1f8f370a0c28555fb8e67557c901d937b937123b28efa6692ed3c649e34fcdaf' WHERE version = 20250425000000;
UPDATE db.migration SET content_hash = '4197ac2342df3e0bf49ed3d32729e415b4db7250989657024b81bebd10aca2ab' WHERE version = 20250429100000;
UPDATE db.migration SET content_hash = '7f4e0183d655a1e427a81b6a50f2d6dd33e53e36a7b7fdeaed8b104c7d5c404d' WHERE version = 20250429102000;
UPDATE db.migration SET content_hash = 'a50f3b14967e9ae9fbef9e003e1600830cfb235fc986ca4b0498e52b7e0027f1' WHERE version = 20250429103000;
UPDATE db.migration SET content_hash = '8845eaa459b4e5c823523b7fa35403e647f17ec6dd9653f5eaccbaa8279185c0' WHERE version = 20250429104000;
UPDATE db.migration SET content_hash = '5ab2548ada7d4c1b4828135a952d1f3d2001677409f460881b59eca32f4c4ecd' WHERE version = 20250429105000;
UPDATE db.migration SET content_hash = '99d845f465bc1a2847d29a4de897414d05d2183bef63d04350f53bed65bc6c44' WHERE version = 20250429110000;
UPDATE db.migration SET content_hash = '79b191e90c15f964889bd9756b7fcae636561e7b0608a2ba3554564262257521' WHERE version = 20250429120000;
UPDATE db.migration SET content_hash = 'c4b359bc85e33e5ef9e3f2c2036e9f1d5aa3140ab623e49ae6bb666635ba33e5' WHERE version = 20250429123000;
UPDATE db.migration SET content_hash = '6da28be6e94573ae2db73d8bbb3e7ea666127d1cf71ab5314cc9deb8a73f6e8c' WHERE version = 20250429130000;
UPDATE db.migration SET content_hash = '6f64370d7aac2426877ad9249950ff305b9003696873536c167a789118abfa7f' WHERE version = 20250429140000;
UPDATE db.migration SET content_hash = 'abea230d15bc29075e2b5e64ed7d3655029c6401ee59419fc3d6d4ff2e03b2ab' WHERE version = 20250429150000;
UPDATE db.migration SET content_hash = '8d4ba7c944b7912f264a8a110a96629db79a09bd21b0c7223d9ee67887d1a727' WHERE version = 20250429170000;
UPDATE db.migration SET content_hash = '768cb4a9a59fa6a63fa9e0cc91f26462a261e9c328f499b1ce3b990063bf177a' WHERE version = 20250429180000;
UPDATE db.migration SET content_hash = 'be503858c42e583acdd7bdf7057e5704af33ae97c4c07e8d3f4b14df4765082e' WHERE version = 20250505100000;
UPDATE db.migration SET content_hash = '23d37e980466a071c0d003bae130ba382f39742a3a9b0073c4895dfa4da8311f' WHERE version = 20250505110000;
UPDATE db.migration SET content_hash = '300212acc35eeb3c87e4c1debc2842a31d097b7d5081128c099b10cb3019a442' WHERE version = 20250505120000;
UPDATE db.migration SET content_hash = '81fbb68d1993708d72a4963407a758d74c3754016fd04060349c75de19f5da53' WHERE version = 20250506100000;
UPDATE db.migration SET content_hash = '95cf1d9f219d69ee57b59296fbdfa0eac87e54902a488c5b1848e7318a4b022a' WHERE version = 20250506110000;
UPDATE db.migration SET content_hash = 'ea02d50d6fc885a56b22485bde458575698b12fdca1eb2092c5e192dba7a1393' WHERE version = 20250506120000;
UPDATE db.migration SET content_hash = 'c53c509891cfa23145fcb1a0c74a6a558ed94f5b497cd46ed0158d94eca2e623' WHERE version = 20250507000000;
UPDATE db.migration SET content_hash = '7e356e12605f5d356a7de457c55ff24d881691866ed266b90ac074d82ced70a3' WHERE version = 20250508000000;
UPDATE db.migration SET content_hash = 'ee61add66864af084a3acc80fca874e5e302bcfa4eab8a0d0406e5db7d0b9fdd' WHERE version = 20250813145500;
UPDATE db.migration SET content_hash = '1d27e2d97cc8d98ef67bef81d5172ed1a9a9c3cab29dc53501f66e7285de1c0c' WHERE version = 20250814110000;
UPDATE db.migration SET content_hash = 'd7f61b0117ebf89fb8dca54c8e19bc19c6530be5fed2cdac4e5c4fde14f777c3' WHERE version = 20251002054000;
UPDATE db.migration SET content_hash = 'c3b6f21097a44ebfeb4220bcfb8bc738e3b64bb38ffdbdb5ba13a567719680e8' WHERE version = 20251110000000;
UPDATE db.migration SET content_hash = '5c4f0d7e3efd48f50e17be134add91143bbd515a3bcfa90c0c99576863ea2ac2' WHERE version = 20260107130806;
UPDATE db.migration SET content_hash = 'a89f9354bd78d2faf8fb5b7b444987e23327b6ce210870097cf5754b10c86efe' WHERE version = 20260126000000;
UPDATE db.migration SET content_hash = '3faef36336da54223d56583c717d8a4ae8d0dd906e6765a5db256fd62281c424' WHERE version = 20260126100708;
UPDATE db.migration SET content_hash = '16e4d7734799c75ae1c6d39c0eb0abdf089ac74939d6eef5b07e001d396e8b7e' WHERE version = 20260126143336;
UPDATE db.migration SET content_hash = '0a03f7b1c94b3a0400823346818a7b83aa7845dc1f29028e1412a3a745e02780' WHERE version = 20260126221107;
UPDATE db.migration SET content_hash = '08470122e7466a8c90dd4c14cb595325a11215eb7d1c01e2fc7ca7e91eafb1f3' WHERE version = 20260127000001;
UPDATE db.migration SET content_hash = '7257524a33d03b1e7f1f7640a931c14a99a7a2c4aac21e424c52856867afe40b' WHERE version = 20260128225812;
UPDATE db.migration SET content_hash = '6f30541b571db8e859b45133c7cad16812365804c36adc085fd13ddca681c166' WHERE version = 20260129150046;
UPDATE db.migration SET content_hash = '4eb0b2f76dc14cd6134e3fe743a52b61e80405165131ae1c7c248f2fa8119fa3' WHERE version = 20260131220347;
UPDATE db.migration SET content_hash = 'b67c342183065c4c4f2139933a33f38fae2fcc327b4c325462c7cf88e748624f' WHERE version = 20260201003119;
UPDATE db.migration SET content_hash = '1e5b1e0c933ca91b7de6945c26c53925ddd8177eb2628630fca59e8cc24d46e4' WHERE version = 20260201011524;
UPDATE db.migration SET content_hash = '0620402cd5bccdb64bf6f48ddfd1238175e8070fee43f9060fb92631f03d861b' WHERE version = 20260201085451;
UPDATE db.migration SET content_hash = '0a131f8168f0cc1fdfc5f74a8f032843cd32b35299a3f2f54e6f4e65ba6f7f8d' WHERE version = 20260201145821;
UPDATE db.migration SET content_hash = 'a7df33dd03774fb90041d500c6ef2c9ea8d79b5f85848c12ee727cb287347b76' WHERE version = 20260202142611;
UPDATE db.migration SET content_hash = '04c204936b22781bd57b6411e659d26c4d9caa2c44700407421f00d31707b70c' WHERE version = 20260202203218;
UPDATE db.migration SET content_hash = 'd4c68a311d66b5bfc99037d1dc8058cea2f48090cfa0fbb176507c2ad0b2aa70' WHERE version = 20260202210959;
UPDATE db.migration SET content_hash = 'de87ddfcb36ac9739420b75576fd8c788c254c57ea43ba229151d1ee94b55ed0' WHERE version = 20260202214243;
UPDATE db.migration SET content_hash = '7ceeb428acec580786e26733b515a8674cd93b8ba7eff2043b7407ec7c36c3ce' WHERE version = 20260203094412;
UPDATE db.migration SET content_hash = '66b666c1f255b7107b56a95c31557d73966c260ac33cdc95aceaf327ef29290f' WHERE version = 20260203113417;
UPDATE db.migration SET content_hash = '2ef1a4998e00bd2654e00fe8ab89e9bc91fa64d1a28ebeab591bdabe2b4f2f77' WHERE version = 20260203131143;
UPDATE db.migration SET content_hash = 'd0808cc459c6f0fca1145313747751d906b4929c90ee8c4b316ed998dbf14fc8' WHERE version = 20260203134134;
UPDATE db.migration SET content_hash = 'ee843d18b71771fab40c29f49c17a27e365e60e08e6889c343a00b0aec390078' WHERE version = 20260203135656;
UPDATE db.migration SET content_hash = 'ddf78f885176afee15212df423aa52aebdb22d5c8d5436db26711d851a3db7ef' WHERE version = 20260203144559;
UPDATE db.migration SET content_hash = '3d9b5147053c9488378f8011a35cf09d39e60527462e68d048e894ef142e7656' WHERE version = 20260203145248;
UPDATE db.migration SET content_hash = '0b27bbe818a2a2ab495f08b6869e151e1268de9895ddc3ca9888c01fedd66aca' WHERE version = 20260203165920;
UPDATE db.migration SET content_hash = '44b6489cea9f394268f0860805f56982061d81175ff5bb33b89cf89cb6bb3738' WHERE version = 20260203170139;
UPDATE db.migration SET content_hash = '73db9fb6daec75a5f177e56c3603844298cce7a1aaa9531f70a50ce4f80ef626' WHERE version = 20260203174306;
UPDATE db.migration SET content_hash = '3b5406cebb168fa540bb8b29b81423aa367446e4ec31511881f2d63eb1a441c6' WHERE version = 20260203221353;
UPDATE db.migration SET content_hash = 'deb0500a649e97282a6b3d760fd7cdea70026c22e930379a161924f4b25ecebf' WHERE version = 20260203221612;
UPDATE db.migration SET content_hash = '9ed51a977e97874fd0acce259c2c2d9c10745281317ac176482728514da306c5' WHERE version = 20260204004935;
UPDATE db.migration SET content_hash = 'b52890149e3ce4a0ac49c91a56ba34c3f32e28ca7b0c4e77860dbe2012cf43c8' WHERE version = 20260204151009;
UPDATE db.migration SET content_hash = 'be5e65ebc807b8fedb9dc31f6142d69d02754ebb9a5f97d9111880d675860d25' WHERE version = 20260204211329;
UPDATE db.migration SET content_hash = '58a49f85d41bb57e0a83f6713453ec997acd3860f908f0948a7e416d44129800' WHERE version = 20260204234245;
UPDATE db.migration SET content_hash = 'b7d6814cd7ca25aea42691bfaec86ae421055535d7c8bdd7734e771f59558e07' WHERE version = 20260205022156;
UPDATE db.migration SET content_hash = '8c21d79cbf012b48b7d903da331c91f9cce9b89e0178766afc589a6de0868ab3' WHERE version = 20260205122909;
UPDATE db.migration SET content_hash = 'bd850e7a70e141180b236bb4a78435fb7897bf1008ac5861a17929f646f7aea8' WHERE version = 20260205140359;
UPDATE db.migration SET content_hash = 'a5c42b93722886778da2113faf0cd7decd33f24386815c5eb78931d95f8f174e' WHERE version = 20260205231027;
UPDATE db.migration SET content_hash = '79d6685eb92bdc60f4e4d9e283e5661558cf40a50bc10ea4e90a8f8832854bf1' WHERE version = 20260206211707;
UPDATE db.migration SET content_hash = 'a81466c446b7bd987e66f7bfe755749387e2009d53f0fa15bf862b51cdfa5c45' WHERE version = 20260207215705;
UPDATE db.migration SET content_hash = 'eb04b41245b5be9ac1124ff1ea6f377f8581078d5c4c74907dcb987d57583d4a' WHERE version = 20260209080204;
UPDATE db.migration SET content_hash = 'ac5bae0bc7b184a8e60666d214b0a9bf4c5a3b6b883f47cc6b26375b3edc2d54' WHERE version = 20260209124424;
UPDATE db.migration SET content_hash = '6c531baea006020fa9d8c0ebd6b192333ee5ca0a3f9061518db7f72890b3e35a' WHERE version = 20260209191636;
UPDATE db.migration SET content_hash = '1d83b59747680af5f6449f1125a9519f5c036123910b15b29293f03f009c9cbe' WHERE version = 20260210121155;
UPDATE db.migration SET content_hash = '001cc213e2d46e177ca97113458b72a87fb8a3b3ba8108874e528bf4797d5d38' WHERE version = 20260210193343;
UPDATE db.migration SET content_hash = '0e36499d3e2dc6e81b04ba2923ea5dfaf265292d99b1c07b27c0254c179d4ebb' WHERE version = 20260211203756;
UPDATE db.migration SET content_hash = '22cdf350bd22c28ea9cfa8c6c3b72a4dff5c37e708dab83e91831c326ee5f699' WHERE version = 20260212072214;
UPDATE db.migration SET content_hash = 'aa96fa5cab1396a50e3401cc70dd73f9727971a06dd749d4af7e0b73fa43d6cc' WHERE version = 20260212123759;
UPDATE db.migration SET content_hash = 'fde620448b0eb2e622e8c78cf6766100788b2244525ac9f9346cebc061dfd6ab' WHERE version = 20260212220011;
UPDATE db.migration SET content_hash = '36afba4dab804c687512f7367cfdebf5e2b4010284ea3e0bbc4dcb3d68cc5e9e' WHERE version = 20260213114048;
UPDATE db.migration SET content_hash = '8b6c8830641a062eaaf3476c01b235e5665b4e9fdcaf278fc6f56b54a96ef82a' WHERE version = 20260214123339;
UPDATE db.migration SET content_hash = '0e94bb10109e34f3603e4de36d3ce6ab764749cf3a17b75455c8cb4fc3de12a6' WHERE version = 20260215150128;
UPDATE db.migration SET content_hash = '6ff0f3c7a206391515521cc146484cb95c904cc5af2693e5208b0f5ab322c083' WHERE version = 20260215150612;
UPDATE db.migration SET content_hash = 'adad4e34dc4d3a8e46d3dd5e129175e1823cd59f01566afa5cb37b0567bfebb5' WHERE version = 20260215150752;
UPDATE db.migration SET content_hash = '9e0201a98eae4f46ef4ba9f867dc2dbd1485c20e52f8a8ea632371d21552c3af' WHERE version = 20260215151259;
UPDATE db.migration SET content_hash = '34179ddaba13688b3315c1ab1981752d28b92b5567294639b7b2af8f7adae869' WHERE version = 20260215152154;
UPDATE db.migration SET content_hash = 'ca3ebab88b459692345f2db7731666a4bea740ce20730e33837bd1c2f081401c' WHERE version = 20260215164215;
UPDATE db.migration SET content_hash = '6b7f01f8e9fb23a6948bdb206402467b80c36d231c44f09a7b91bfa925ed3d13' WHERE version = 20260215164911;
UPDATE db.migration SET content_hash = '66b6182aace67267915a220ad7a6ff781c4fb0305425346a10772d73e6bce594' WHERE version = 20260217165415;
UPDATE db.migration SET content_hash = '073edba9ebc20843d80219ce84d525e8d5c1ef099808e27f553cba78ff424a99' WHERE version = 20260218085806;
UPDATE db.migration SET content_hash = 'daf2cf26e3fbd9e86380de55fe6edb7e0d7003a3b32d707973ad9aa0ecf8eb39' WHERE version = 20260218090000;
UPDATE db.migration SET content_hash = '2cbb8a9f43b36b9a8d0a80946469c2e67db14bb2c3308b0aa60fc009572cb373' WHERE version = 20260218090001;
UPDATE db.migration SET content_hash = 'caefb25117ac2f4871cea8921973631224400edc6a0a718bcb5d4ff0f8c50cdc' WHERE version = 20260218090002;
UPDATE db.migration SET content_hash = 'cd82bc76e09bcf24544a1a3a8bb03597d7323ce1aab357c18e6e7ca3c936b46d' WHERE version = 20260218215337;
UPDATE db.migration SET content_hash = '921c1fe54cfd1adcc6bbb49933145f43b46f3e8a981a52f6fdfa2c470835f46d' WHERE version = 20260219121154;
UPDATE db.migration SET content_hash = '3736a29004de2bfe21969069d8b66840a8108c2b46f7be073556d78b0c4c5b91' WHERE version = 20260221095033;
UPDATE db.migration SET content_hash = 'f031aa1500d940b438d0744dad03098126ab316ed1b9225509352502e2773c45' WHERE version = 20260222154306;
UPDATE db.migration SET content_hash = 'a155fb831a5dc07abeff3ef326f778a03318d0e7afee1e7632f216b4cee012de' WHERE version = 20260223070633;
UPDATE db.migration SET content_hash = 'b3173eb1a0d04d1cf025fa023bebdb93117e81fe2b0f43c780a8f3fc05909357' WHERE version = 20260223185108;
UPDATE db.migration SET content_hash = 'cd7f25c07c43a4103c4e84046a793b5cfa35e212ea472e8a07def9c018383822' WHERE version = 20260223210911;
UPDATE db.migration SET content_hash = '1037a7589dccdd6b96850e1f5e0d207dcda915ed85b31411081a6b4c871d50b1' WHERE version = 20260224090257;
UPDATE db.migration SET content_hash = '9ef3bf6458322ae5c7a813534fa97ae5c71fe790d27d14e01682ec5024e62233' WHERE version = 20260224113002;
UPDATE db.migration SET content_hash = '5e59afdbff7664b19eba03738f8d3604b3162bdb5646c1e7472c36deb31327b4' WHERE version = 20260224121227;
UPDATE db.migration SET content_hash = '241661ed0c7df70c6d074b9d4700811cbfbbc81271c81db2ac22851bf4d0da5b' WHERE version = 20260224131241;
UPDATE db.migration SET content_hash = '16da415c334d7fbd19e71917905ed17631c5a89015f18759f3802eeadbde7c0e' WHERE version = 20260224191329;
UPDATE db.migration SET content_hash = '14351078abc8939a07c063fa940f1f71788040bbb54b8baf55c4248e8e31ba3c' WHERE version = 20260225135926;
UPDATE db.migration SET content_hash = 'f64328f65d4f135c8d5bec1659eebf015ae1ea56b7933c1258be43c6361e3da6' WHERE version = 20260226000000;
UPDATE db.migration SET content_hash = '76ff77f394a7290b47818cbbdeaaf3d682c6945dc81a969f2e5c40ef3dc213ab' WHERE version = 20260227102355;
UPDATE db.migration SET content_hash = 'be130fa00050186e6918a613b31a5dba3379ba35607e5dccb70f31bd43d180e5' WHERE version = 20260305191438;
UPDATE db.migration SET content_hash = '0fc6ad844ac16b9655c67cb37a20c3da8ae62f385a5eb2f2bb735292058064e2' WHERE version = 20260306154720;
UPDATE db.migration SET content_hash = '50a132b2c2c6f7cc6d8bda92a8847490415fad9cf4892244dda2a56e7e93622a' WHERE version = 20260308184452;
UPDATE db.migration SET content_hash = 'a52d59c09012d09c323cb8dac3181bb65bd62be9b12f21eebde055f7f73d7ab1' WHERE version = 20260309140143;
UPDATE db.migration SET content_hash = 'c8efd7c199355aa18ec0c36e81d7f33ef9c9ac904074a1d156af02ee8af14517' WHERE version = 20260310111815;
UPDATE db.migration SET content_hash = 'cb2421b16f96d4091626d5a79a2e0fdfc938dd1c38deb423ba4f2b5ed3e57e89' WHERE version = 20260310112934;
UPDATE db.migration SET content_hash = '4d5cb1cd2998d9d3d73f8e656fafb4162220b34db5a8779c8f7c768d30df7010' WHERE version = 20260310132309;
UPDATE db.migration SET content_hash = 'b31a7589659628942f1bb2978ebfe680011b5fac58a8c1ccfe039d1e0e2a6b4b' WHERE version = 20260310140518;
UPDATE db.migration SET content_hash = '529ac8560ed995095dc5156dd8a1569967c5dac60e6bfd3226504bff71ca5bf9' WHERE version = 20260310145700;
UPDATE db.migration SET content_hash = 'e6ecc58223461db387c16f4ca2c90071125a9f11c70509875647107eac2a64e7' WHERE version = 20260310150000;
UPDATE db.migration SET content_hash = 'cc80e337f37d49bede23df77d7df664813fc8ba0fcee4f9c4c1c4b5bda1a68a5' WHERE version = 20260310150100;
UPDATE db.migration SET content_hash = 'e2cb7acdafaf27d50606719ab4e0c99e4be3f0714d332cfb7e69c2e26c267eae' WHERE version = 20260310150200;
UPDATE db.migration SET content_hash = 'e2b8d04bc1d02121de040ee5d4dba78a8ef49c44fde898f281e887bb66a320b7' WHERE version = 20260311102131;
UPDATE db.migration SET content_hash = '6a09bcc4c38b949e3ace627acf5a97f09eedbdf0143984800873abb954e132e1' WHERE version = 20260311174120;
UPDATE db.migration SET content_hash = '0c93a9a5f3972775b792441fe67107961ecf44fa2f25a0a57a80eceffbf010c7' WHERE version = 20260311220000;
UPDATE db.migration SET content_hash = '6d3daf668886bc627e820d9f1c3c4bb140c463c597753b034aaadfbbcdf3636c' WHERE version = 20260312114520;
UPDATE db.migration SET content_hash = 'dffaeba2422b2c2c25a329bfc60b336c90422e1b71b61aefb18dfb681756f731' WHERE version = 20260312114521;
UPDATE db.migration SET content_hash = '385a9b00f8f50e2c8861396bd694aa78c68d48d632cba5dd41200f893ccf3d61' WHERE version = 20260312114522;
UPDATE db.migration SET content_hash = 'c24b77b2b32d3cdd3689da83aa2349be3835dbb5c1cc476e8a9dc913d780039a' WHERE version = 20260312114523;
UPDATE db.migration SET content_hash = '0a1d0c13987cc2e9647ea84f510e0d595644f344cb963d37714877c78e2d8c1d' WHERE version = 20260312114524;
UPDATE db.migration SET content_hash = '75bb20cc812e8d478d787a5b34faafd432b7fe9728237fa6fca57ece33e18fd0' WHERE version = 20260312114525;
UPDATE db.migration SET content_hash = 'cae9538963c4c6501112ba057ca547e20648ee7321b83bb509a72c202c35aaa9' WHERE version = 20260312114526;
UPDATE db.migration SET content_hash = 'e25bffcd176fafca7359eb77cc92dc59d520b1e46230361c3209f7143bfab4cd' WHERE version = 20260314113637;
UPDATE db.migration SET content_hash = 'd487f95f8b019e48b63f602122106d82e29c6d22c8814ccae1655c9726172c02' WHERE version = 20260314210000;
UPDATE db.migration SET content_hash = 'bbf88c048bb8b9f435de1bc4e76099d5bcf480f3fbaf2e210d60f950b19d089f' WHERE version = 20260314210001;
UPDATE db.migration SET content_hash = '387b6d9c643adcddc963ca0f949f117ccc756e8ae21095d194b69cd2a1f403c5' WHERE version = 20260314210002;
UPDATE db.migration SET content_hash = '125d69c9b9cb4b67ccbe7024a99c52c96512bb8f005f3cbfab9a8ba09a7f9f15' WHERE version = 20260315000000;
UPDATE db.migration SET content_hash = 'b7ace547821a9e7e5f9c836ba5ea75f3118eeef078d533d98ace89114db255a9' WHERE version = 20260315013241;
UPDATE db.migration SET content_hash = '1a2883075d605d81cc6a684675e77b599d3115567ce97df59dd63d0876f53559' WHERE version = 20260315201236;
UPDATE db.migration SET content_hash = '2cd02bf22b53dc79b35aeaa719624e52db8f4b1c730e119b98a6855f65ad6ede' WHERE version = 20260316103248;
UPDATE db.migration SET content_hash = '56c823c87317690d2b5079d0676f66f3ffbaacd8419e7a3f25e7d19b1ec03109' WHERE version = 20260316131326;
UPDATE db.migration SET content_hash = '55e0477b1e177121bbe4eaff2c9748879cdb7896a1e200c726fff974a8c87ac9' WHERE version = 20260317060914;
UPDATE db.migration SET content_hash = '1156d91b1b0097289933156f732c374da922199038ceac7fdac468534de83b69' WHERE version = 20260317114643;
UPDATE db.migration SET content_hash = 'dd9a98b1b09ee12c6d0fbfe976fe23c2aa4d9bc73296496e718d79d0100c09fb' WHERE version = 20260318040138;
UPDATE db.migration SET content_hash = '14fe600e9da9daabdc39caf99308d47fcb7e72a1a2856540a3400f88f5f2295f' WHERE version = 20260318042909;
UPDATE db.migration SET content_hash = '9c486b3c441643dc319d6db349104f1883a39297e5eea28704e73a6e59fd73d9' WHERE version = 20260318134111;
UPDATE db.migration SET content_hash = 'cbe37b1f36d4cba9bd039f48f7306b79fc13aeedd1136ae65d01309a82b8ff14' WHERE version = 20260318134116;
UPDATE db.migration SET content_hash = 'b335b19748826761eb0e29a78fcade699d3cd5657c0933274e5e1d8c4e7e34df' WHERE version = 20260318143644;
UPDATE db.migration SET content_hash = 'd11d0320e8941e77be4d801ade6ab2849651e67074fa4b2555d4e15540ba08ee' WHERE version = 20260318173625;
UPDATE db.migration SET content_hash = 'c1c67a18de4211bff6d863fa08d841e07c6ac2b198c8b565d1fbc707e73e3695' WHERE version = 20260319124229;
UPDATE db.migration SET content_hash = '5420b7d1de7b7d45765030eee0da8c7e38baca2a0da891cd1648c58d48ccc7f7' WHERE version = 20260319170725;
UPDATE db.migration SET content_hash = '00083aa8912c033aea17752793887a48530ba1727bf126cf669f30cbf73c1cb9' WHERE version = 20260319221604;
UPDATE db.migration SET content_hash = 'f4f28c06698077b58ba53b16275c3695040353b1c32b07f95cceb25e08818035' WHERE version = 20260320000050;
UPDATE db.migration SET content_hash = '424f4ccc64f2a3de232dab48fbc37ca5676a81c2e3dd648c24da8a61ef87d449' WHERE version = 20260320011715;
UPDATE db.migration SET content_hash = '278e8830ad0d6b276fa15a0ee88dd6b9f99a8f3c36cdf00e87290f69b7f0b6e2' WHERE version = 20260320021106;
UPDATE db.migration SET content_hash = 'fca65c951b27e9bec5b26329baf7ee458bc5ebb41fccbad6e3ea073748dc16d6' WHERE version = 20260320102510;
UPDATE db.migration SET content_hash = '3a9854fc680664bd3b333ba87cd9c6f2f9dcf2549420503c6bbcaf171048b9c9' WHERE version = 20260320105936;
UPDATE db.migration SET content_hash = 'a70588fca6da72cdde33c341bb2dccb2309ec07796d8154f21f86e8660929bd2' WHERE version = 20260320110615;
UPDATE db.migration SET content_hash = '89911b0f683ea64fcae3126efb95ec6c71d06fd903d9bb79fa2007c61b332f1b' WHERE version = 20260320115108;
UPDATE db.migration SET content_hash = '80d3167bb413f9817e72e1e02e76af7945d9d871895cbcbe95b3c7ea41a9ee5f' WHERE version = 20260321180348;
UPDATE db.migration SET content_hash = '2d3222f01010248bd85f08c9d10dfb8e40d6c07b86e3e7da3987c8aa40fa4cd1' WHERE version = 20260324143316;
UPDATE db.migration SET content_hash = 'ba838d2566a9656b19c87f3ee389b267fc039dc99533c1ee4c61f3d10176557c' WHERE version = 20260324144003;
UPDATE db.migration SET content_hash = '538b3a8459f71cfe7de533f1a8c75448ca2b0e56f640ec536a0b5096b17419ed' WHERE version = 20260324144302;
UPDATE db.migration SET content_hash = '3baacd3ed183d184175ccbd0aa2e801c80f4f0a9712ad1fd24212337b9143b0c' WHERE version = 20260324144548;
UPDATE db.migration SET content_hash = 'e02be41d987d91b98a545a4515ac43b5fcefc7bb05ebc83998c752d040977620' WHERE version = 20260324144549;
UPDATE db.migration SET content_hash = '6761c2e18f78ee83e92b5ffd729973f81f061d2ca0c00ca3c96f46b8fea3d535' WHERE version = 20260324200723;
UPDATE db.migration SET content_hash = '63559e86e2485cd830452337720979ee8742f1ee3e6a786e297d57424c339ace' WHERE version = 20260324203631;
UPDATE db.migration SET content_hash = 'c1090340609d6aa31493a5cf37d849a4449cc8e443b8cb1c82064c0a4c08e165' WHERE version = 20260324224225;
UPDATE db.migration SET content_hash = 'ff7bb2b7559c7f6cb803d0bff58db86fe9d76706e736127fcf903b5b227c945d' WHERE version = 20260324232001;
UPDATE db.migration SET content_hash = 'f8fc41576e4a2364ecc5973abdbc3bbee29447619c1649bbd3f1d035b7bf266a' WHERE version = 20260325011559;
UPDATE db.migration SET content_hash = '0590c4af75d3fd0f36430ca23abf5e6389ca3847f1cbab82abac8e509d0e9d58' WHERE version = 20260325114130;
UPDATE db.migration SET content_hash = '0749f53ccc103ce3facd72c134bad4f4872f1e5383acb41a9ceb4908b75cd5de' WHERE version = 20260325230737;
UPDATE db.migration SET content_hash = 'cbfe416cc54e488b8a123006e6bb387b9952a386e83851cb4b2bcc267f24a131' WHERE version = 20260325235200;
UPDATE db.migration SET content_hash = 'fcb5fcf351e48f9994b51b46c3608b944336b6e89c197c9512f1d7585de8511a' WHERE version = 20260326004538;
UPDATE db.migration SET content_hash = 'a711b8bdca919f201d5c89788f50e78106998573f1fc3dfa3bd55fa04125c444' WHERE version = 20260326160507;
UPDATE db.migration SET content_hash = '0bb6f02f111e92f618a29de76ef5b1959117a25064f6e8da7781c3d752d022f1' WHERE version = 20260326161813;
UPDATE db.migration SET content_hash = '4a57c39526d0dbdbbcabbcac29f7505a8a250fcd79e09cc9e27f06e7f6894e8e' WHERE version = 20260326174816;
UPDATE db.migration SET content_hash = 'cd50b3131600fc72113b56878970fc5eb935465240761263fb0f4308d81b0606' WHERE version = 20260327152214;
UPDATE db.migration SET content_hash = '7919315b17a5520ecb68421bcd23057c2a8c796a5cb86ae82b7b95f4baf4cc47' WHERE version = 20260327214113;
UPDATE db.migration SET content_hash = '2af626de4aa44181ab38925f64cd94497875d3494ecaa9a1660830a152c274d9' WHERE version = 20260328000022;
UPDATE db.migration SET content_hash = '99ee7cb2bbebf7aa2bdf51772ac9e43e7ccde16f5b921190cca9cb333bee9bf2' WHERE version = 20260328092344;
UPDATE db.migration SET content_hash = '30694b6fcb532f97c2680479545a54e22a4d7677cd8b8cb09229a1b9f5390ad0' WHERE version = 20260329000000;
UPDATE db.migration SET content_hash = '08bb221978f824b5862749330591416014a49c6a2f0db950f37008de6bfbfe8c' WHERE version = 20260330193847;
UPDATE db.migration SET content_hash = '2147d5f6fffd0dae19f722ebe0b89bae66c281a11f8b32e9824a7eec9f89e0ce' WHERE version = 20260331161820;
UPDATE db.migration SET content_hash = '00dfb6d2247e763a4f89d58d15451ef43e12eb939850f8ebeca078ef1aa517ee' WHERE version = 20260331171938;
UPDATE db.migration SET content_hash = '2ad83f059159963d6f25df6dfcbbdf8ee3aa216211c0bef314f01b6f760979cc' WHERE version = 20260414162000;
UPDATE db.migration SET content_hash = 'fad4e4b7209e2f7f0253603d174babe424e922a376bd8b7b4f6b925195a25144' WHERE version = 20260414170000;
UPDATE db.migration SET content_hash = 'b6ab2e953d8eda6b8d587096dc380a5144af54f2efd49a5c8f94061842241862' WHERE version = 20260414170500;
UPDATE db.migration SET content_hash = '6b16a1e8271839acdd36b3438c9ee8388a3199d8dcfcd2703e53c781266331b0' WHERE version = 20260414180000;
UPDATE db.migration SET content_hash = '86c47d2f9956115a15358207b14752498ab61873941e7eae79ee34714d789961' WHERE version = 20260414193000;
UPDATE db.migration SET content_hash = 'fde3bb100e993e7914c4367c16a4d181d09dc0a25771892d7c816b0521127f8b' WHERE version = 20260415120722;
UPDATE db.migration SET content_hash = 'fa47c6776d99e25e88a23cebae7642327462af1bf5a3cd3dbf1a835bde2e66cd' WHERE version = 20260415123856;
UPDATE db.migration SET content_hash = 'fceb54b8ff38cccf348711a526a8b8c52eed33ac60f97e5790a61ce947431d54' WHERE version = 20260415141454;
UPDATE db.migration SET content_hash = '798693f7d171833ed5511eb8394732f235b4dff217c1bc9719ffa1cf9467663d' WHERE version = 20260415183106;
UPDATE db.migration SET content_hash = 'a0cde73a389d9c5c1ded805fc4239a7b665f61152dfdaaebece3e2d52795df9d' WHERE version = 20260415220000;
UPDATE db.migration SET content_hash = '37579e5866eb8be53f7fe7dc29e211ac817b27fdf79de12b76184ba5e913cc4f' WHERE version = 20260415230000;
UPDATE db.migration SET content_hash = '95836d9e4b7dd8c0c52eb3d44b456908979405fd0be46d50ffc21e363683bac4' WHERE version = 20260416112355;
UPDATE db.migration SET content_hash = '72ec4999b0007d80d8474a69ad4e6c37f4b3e5e32eb5cbe1ba0292c9175d5738' WHERE version = 20260416120000;
UPDATE db.migration SET content_hash = '096157db1a1f38d2084b5869bb0c56627668fae932979db79b44c4986458de5b' WHERE version = 20260417085502;
UPDATE db.migration SET content_hash = 'ae4a0040dede894f17216193e9287da35398732dc15516b72b423b755e15d66f' WHERE version = 20260417105000;
UPDATE db.migration SET content_hash = '3ebbcd7648856ed09099c782bc571edd2b7f405803ce71969a273a9dc985161a' WHERE version = 20260417130648;
UPDATE db.migration SET content_hash = '2550d15d3ecf5fa743e9266306b7105aa128f7b819721402a19f0fabf18ac6d1' WHERE version = 20260417133216;
UPDATE db.migration SET content_hash = '6fc7f30d622c999bbc17879bddbde473539560e66a5f19066c1cf0a493998843' WHERE version = 20260417163407;
UPDATE db.migration SET content_hash = 'b401da43aabcfc58d027d6b4bcd13ab94b4c857da9e420a79c6bb48515e09a53' WHERE version = 20260418204304;
UPDATE db.migration SET content_hash = '89715caabed1e260bc7a9709a67a83ca42370d222394473a30debce56bbae440' WHERE version = 20260419114853;
UPDATE db.migration SET content_hash = 'a21d30662f661d457a389803f83c4193ee13454f00671c38f0c852da6c2dca32' WHERE version = 20260419131746;
UPDATE db.migration SET content_hash = 'b86bb1b03efde9433e3e45b73e5991a5018ab4f93c23a1f8585960e7271073a2' WHERE version = 20260419133000;
UPDATE db.migration SET content_hash = '1822c2aef2a0f53e4f4456c01e14ecbe1b82379f53e524746dda01622a54ebf2' WHERE version = 20260421113651;
UPDATE db.migration SET content_hash = '07742cdf657fedccca9e2d5b88b6a0777f7566d102e43bd030ee7e558de7c7f9' WHERE version = 20260421113653;
UPDATE db.migration SET content_hash = 'edd9d8aa4c5c0d28aec4949521b7f0c9de09400e9f4260165ce4f90dfaa03fca' WHERE version = 20260421155421;
UPDATE db.migration SET content_hash = '33383218e9997cafceca466481179264e2ac21adca890f2f679f0c0c9c77dbb0' WHERE version = 20260422000000;
UPDATE db.migration SET content_hash = '79819b346634a5d1a527c043ebaf1758db465b8db623cf0570e5572b20009707' WHERE version = 20260422011930;
UPDATE db.migration SET content_hash = '7fdf03ddc77e4786241719e964fe1e238ab82aef186e04d1216398d6b01bd2ae' WHERE version = 20260422080000;
UPDATE db.migration SET content_hash = 'ad3cd7b8c8ab32589a5a569b9b410e2f1a2e664799dca60730bb036cfcb128fa' WHERE version = 20260422161000;
UPDATE db.migration SET content_hash = 'a364253d8ab077b1a19e9801ba783a5b21a21c61fe4683aba58fecc2806b9a5e' WHERE version = 20260422170000;
UPDATE db.migration SET content_hash = 'aa0c591ea875123a05ba7851883133745b1d6f9944a3dea4a3885d569ddafb34' WHERE version = 20260423070000;
UPDATE db.migration SET content_hash = 'a5a0c881d4fb06c2bdd06982ad9a7b41f1081c8f32aa3aa0f4758f76d3e577b5' WHERE version = 20260423123858;
UPDATE db.migration SET content_hash = '5df91ce76c320d850bcf7237bba72d22ae917711af0edae6bba20b42ca7c7b14' WHERE version = 20260424160235;
UPDATE db.migration SET content_hash = '1ed34e04d9b1c8bf1f77363b9da57a6046d959d031b44ee53c4754c4b6873307' WHERE version = 20260425163029;

-- After hardcoded backfill: every legacy row has a hash; every
-- future row must include one. NOT NULL enforces forever.
ALTER TABLE db.migration ALTER COLUMN content_hash SET NOT NULL;

COMMIT;
