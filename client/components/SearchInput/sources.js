export default {
  region: {
    url: '/api/regions/search',
    label: 'Region',
    placeholder: 'RegionAdd',
    data: {},
  },
  activity: {
    url: '/api/activities/search',
    label: 'ActualMainActivity1',
    placeholder: 'RegMainActivity',
    data: {},
  },
  sectorCode: {
    url: '/api/sectorcodes/search',
    editUrl: '/api/sectorcodes/GetById/',
    label: 'InstSectorCodeId',
    placeholder: 'InstSectorCodeId',
    data: {},
  },
  legalForm: {
    url: '/api/legalforms/search',
    editUrl: '/api/legalforms/GetById/',
    label: 'LegalForm',
    placeholder: 'LegalForm',
    data: {},
  },
  parentOrgLink: {
    url: '/api/StatUnits/SearchByWildcard',
    editUrl: '/api/StatUnits/GetStatUnitById/',
    label: 'ParentOrgLink',
    placeholder: 'ParentOrgLink',
    data: {},
  },
  reorgReferences: {
    url: '/api/StatUnits/SearchByWildcard',
    editUrl: '/api/StatUnits/GetStatUnitById/',
    label: 'ReorgReferences',
    placeholder: 'ReorgReferences',
    data: {},
  },
}
