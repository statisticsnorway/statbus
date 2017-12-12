namespace nscreg.Data.Constants
{
    /// <summary>
    /// Константы системных функций
    /// </summary>
    public enum SystemFunctions
    {
        // account
        AccountView = 0,
        AccountEdit=1,

        // roles
        RoleView=2 ,
        RoleCreate=3,
        RoleEdit=4,
        RoleDelete=5,

        // users
        UserView=6,
        UserCreate=7,
        UserEdit=8,
        UserDelete=9,

        // stat. units
        StatUnitView=10,
        StatUnitCreate=11,
        StatUnitEdit=12,
        StatUnitDelete=13,

        // regions
        RegionsView = 17,
        RegionsCreate = 18,
        RegionsEdit = 19,
        RegionsDelete = 20,

        // address
        AddressView = 25,
        AddressCreate = 26,
        AddressEdit = 27,
        AddressDelete = 28,

        // links
        LinksView = 29,
        LinksCreate = 30,
        LinksDelete = 31,

        // data sources
        DataSourcesView = 32,
        DataSourcesCreate = 33,
        DataSourcesEdit = 34,
        DataSourcesDelete = 35,

        // data source queues
        DataSourcesQueueView = 36,
        DataSourcesQueueLogView = 37,
        DataSourcesQueueLogEdit = 38,

        DataSourcesQueueAdd = 41,

        // Analysis
        StatUnitAnalysis = 42,


        //Sample Frames
        SampleFrameCreate = 43,
        SampleFrameEdit = 44,
        SampleFrameDelete = 45,

        //Analysis
        AnalysisQueueView = 46,
        AnalysisQueueAdd = 47
    }
}
