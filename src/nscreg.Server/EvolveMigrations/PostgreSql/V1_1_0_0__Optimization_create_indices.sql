CREATE INDEX "IX_StatisticalUnits_DuplicateSearchOptimization" ON "StatisticalUnits"
(
	"ShortName" ASC,
	"RegId" ASC,
	"Discriminator" ASC,
	"StatId" ASC,
	"TaxRegId" ASC
)
INCLUDE("Name","ExternalId","TelephoneNo","EmailAddress");
