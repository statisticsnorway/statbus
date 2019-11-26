CREATE TABLE [dbo].[Regions] (
    [Id]                  INT            IDENTITY (1, 1) NOT NULL,
    [AdminstrativeCenter] NVARCHAR (MAX) NULL,
    [Code]                NVARCHAR (450) NULL,
    [IsDeleted]           BIT            DEFAULT ((0)) NOT NULL,
    [Name]                NVARCHAR (MAX) NOT NULL,
    [ParentId]            INT            NULL,
    [FullPath]            NVARCHAR (MAX) NULL,
    [FullPathLanguage1]   NVARCHAR (MAX) NULL,
    [FullPathLanguage2]   NVARCHAR (MAX) NULL,
    [NameLanguage1]       NVARCHAR (MAX) NULL,
    [NameLanguage2]       NVARCHAR (MAX) NULL,
    [RegionLevel]         INT            NULL,
    CONSTRAINT [PK_Regions] PRIMARY KEY CLUSTERED ([Id] ASC),
    CONSTRAINT [FK_Regions_Regions_ParentId] FOREIGN KEY ([ParentId]) REFERENCES [dbo].[Regions] ([Id])
);


GO
CREATE NONCLUSTERED INDEX [IX_Regions_ParentId]
    ON [dbo].[Regions]([ParentId] ASC);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_Regions_Code]
    ON [dbo].[Regions]([Code] ASC) WHERE ([Code] IS NOT NULL);

