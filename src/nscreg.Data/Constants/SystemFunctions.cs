using nscreg.Utilities.Attributes;

namespace nscreg.Data.Constants
{
    /// <summary>
    /// Константы системных функций
    /// </summary>
    public enum SystemFunctions
    {
        // account
        [AllowedTo(DefaultRoleNames.Employee, DefaultRoleNames.ExternalUser)]
        AccountView = 0,

        [AllowedTo(DefaultRoleNames.Employee, DefaultRoleNames.ExternalUser)]
        AccountEdit = 1,

        // roles
        RoleView = 2,
        RoleCreate = 3,
        RoleEdit = 4,
        RoleDelete = 5,

        // users
        UserView = 6,
        UserCreate = 7,
        UserEdit = 8,
        UserDelete = 9,

        // stat. units
        [AllowedTo(DefaultRoleNames.Employee, DefaultRoleNames.ExternalUser)]
        StatUnitView = 10,

        [AllowedTo(DefaultRoleNames.Employee)]
        StatUnitCreate = 11,

        [AllowedTo(DefaultRoleNames.Employee)]
        StatUnitEdit = 12,

        [AllowedTo(DefaultRoleNames.Employee)]
        StatUnitDelete = 13,

        // regions
        [AllowedTo(DefaultRoleNames.Employee)]
        RegionsView = 17,

        [AllowedTo(DefaultRoleNames.Employee)]
        RegionsCreate = 18,

        [AllowedTo(DefaultRoleNames.Employee)]
        RegionsEdit = 19,

        [AllowedTo(DefaultRoleNames.Employee)]
        RegionsDelete = 20,

        // address
        [AllowedTo(DefaultRoleNames.Employee)]
        AddressView = 25,

        [AllowedTo(DefaultRoleNames.Employee)]
        AddressCreate = 26,

        [AllowedTo(DefaultRoleNames.Employee)]
        AddressEdit = 27,

        [AllowedTo(DefaultRoleNames.Employee)]
        AddressDelete = 28,

        // links
        [AllowedTo(DefaultRoleNames.Employee)]
        LinksView = 29,
        [AllowedTo(DefaultRoleNames.Employee)]
        LinksCreate = 30,
        [AllowedTo(DefaultRoleNames.Employee)]
        LinksDelete = 31,

        // data sources
        DataSourcesView = 32,
        DataSourcesCreate = 33,
        DataSourcesEdit = 34,
        DataSourcesDelete = 35,

        // data source queues
        [AllowedTo(DefaultRoleNames.Employee)]
        DataSourcesQueueView = 36,

        [AllowedTo(DefaultRoleNames.Employee)]
        DataSourcesQueueLogView = 37,

        [AllowedTo(DefaultRoleNames.Employee)]
        DataSourcesQueueLogEdit = 38,

        [AllowedTo(DefaultRoleNames.Employee)]
        DataSourcesQueueAdd = 39,

        // Analysis
        StatUnitAnalysis = 40,
        AnalysisQueueView = 41,
        AnalysisQueueAdd = 42,
        AnalysisQueueLogView = 43,
        AnalysisQueueLogUpdate = 44,

        //Sample Frames
        [AllowedTo(DefaultRoleNames.Employee)]
        SampleFramesCreate = 45,
        [AllowedTo(DefaultRoleNames.Employee)]
        SampleFramesEdit = 46,
        [AllowedTo(DefaultRoleNames.Employee)]
        SampleFramesDelete = 47,
        [AllowedTo(DefaultRoleNames.Employee)]
        SampleFramesView = 48,
        [AllowedTo(DefaultRoleNames.Employee)]
        SampleFramesPreview = 49,
        [AllowedTo(DefaultRoleNames.Employee, DefaultRoleNames.Administrator)]
        Reports = 50,
    }
}
