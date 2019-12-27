CREATE TABLE [dbo].[ActivityCategories] (
    [Id]                    INT            IDENTITY (1, 1) NOT NULL,
    [Code]                  NVARCHAR (10)  NOT NULL,
    [DicParentId]           INT            NULL,
    [IsDeleted]             BIT            NOT NULL,
    [Name]                  NVARCHAR (MAX) NOT NULL,
    [ParentId]              INT            NULL,
    [Section]               NVARCHAR (10)  NOT NULL,
    [VersionId]             INT            NOT NULL,
    [NameLanguage1]         NVARCHAR (MAX) NULL,
    [NameLanguage2]         NVARCHAR (MAX) NULL,
    [ActivityCategoryLevel] INT            NULL,
    CONSTRAINT [PK_ActivityCategories] PRIMARY KEY CLUSTERED ([Id] ASC)
);


GO
CREATE UNIQUE NONCLUSTERED INDEX [IX_ActivityCategories_Code]
    ON [dbo].[ActivityCategories]([Code] ASC);

