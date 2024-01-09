import { checkSystemFunction as sF } from '/helpers/config'

const menu = {
  StatUnits: [
    { sf: 'StatUnitView', key: 'StatUnitSearch', route: '/', icon: 'search' },
    {
      sf: 'StatUnitDelete',
      key: 'StatUnitUndelete',
      route: '/statunits/deleted',
      icon: 'undo',
    },
    {
      sf: 'StatUnitCreate',
      key: 'StatUnitCreate',
      route: '/statunits/create/2',
      icon: 'add',
    },
  ],
  SampleFrames: [
    {
      sf: 'SampleFramesView',
      key: 'SampleFramesView',
      route: '/sampleframes',
      icon: 'tasks',
    },
    {
      sf: 'SampleFramesCreate',
      key: 'SampleFramesCreate',
      route: '/sampleframes/create',
      icon: 'add',
    },
  ],
  DataSources: [
    {
      sf: 'DataSourcesView',
      key: 'DataSources',
      route: '/datasources',
      icon: 'file text outline',
    },
    {
      sf: 'DataSourcesCreate',
      key: 'DataSourcesCreate',
      route: '/datasources/create',
      icon: 'add',
    },
    {
      sf: 'DataSourcesQueueAdd',
      key: 'DataSourcesUpload',
      route: '/datasources/upload',
      icon: 'upload',
    },
    {
      sf: 'DataSourcesQueueView',
      key: 'DataSourceQueues',
      route: '/datasourcesqueue',
      icon: 'database',
    },
  ],
  QualityManagement: [],
  AdministrativeTools: [
    { sf: 'UserView', key: 'Users', route: '/users', icon: 'users' },
    { sf: 'RoleView', key: 'Roles', route: '/roles', icon: 'setting' },
    {
      sf: 'AnalysisQueueView',
      key: 'Analysis',
      route: '/analysisqueue',
      icon: 'line graph',
    },
  ],
}

export default localize =>
  Object.entries(menu).reduce((sections, [key, entries]) => {
    const items = entries.reduce(
      (links, { sf, ...props }) =>
        sF(sf) ? [...links, { ...props, text: localize(props.key) }] : links,
      [],
    )
    return items.length > 0 ? { ...sections, [localize(key)]: items } : sections
  }, {})
