CREATE NONCLUSTERED INDEX [IX_StatisticalUnits_DuplicateSearchOptimization] ON [dbo].[StatisticalUnits]
(
	[ShortName] ASC,
	[RegId] ASC,
	[Discriminator] ASC,
	[StatId] ASC,
	[TaxRegId] ASC
)
INCLUDE([Name],[ExternalId],[AddressId],[TelephoneNo],[EmailAddress]) WITH (SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
