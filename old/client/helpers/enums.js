import { oneOf } from '/helpers/enumerable'

export const statUnitTypes = new Map([
  [1, 'LocalUnit'],
  [2, 'LegalUnit'],
  [3, 'EnterpriseUnit'],
  [4, 'EnterpriseGroup'],
])

export const statUnitIcons = new Map([
  [1, 'suitcase'],
  [2, 'briefcase'],
  [3, 'building'],
  [4, 'sitemap'],
])

export const dataSourceOperations = new Map([
  [1, 'Create'],
  [2, 'Update'],
  [3, 'CreateAndUpdate'],
])

export const dataSourcePriorities = new Map([
  [1, 'Trusted'],
  [2, 'Ok'],
  [3, 'NotTrusted'],
])

export const dataSourceQueueStatuses = new Map([
  [1, 'InQueue'],
  [2, 'Loading'],
  [3, 'DataLoadCompleted'],
  [4, 'DataLoadCompletedPartially'],
  [5, 'DataLoadCompletedFailed'],
])

export const dataSourceQueueLogStatuses = new Map([
  [1, 'Done'],
  [2, 'Warning'],
  [3, 'Error'],
])

export const personSex = new Map([
  [1, 'Male'],
  [2, 'Female'],
])

export const personTypes = new Map([
  [1, 'ContactPerson'],
  [2, 'Founder'],
  [3, 'Owner'],
  [4, 'Director'],
])

export const userStatuses = new Map([
  [2, 'Active'],
  [1, 'Suspended'],
  [0, 'Quit'],
])

export const activityTypes = new Map([
  [1, 'ActivityPrimary'],
  [2, 'ActivitySecondary'],
  [3, 'ActivityAncilliary'],
  [4, 'AsRegistered'],
])

export const statUnitFormFieldTypes = new Map([
  [0, 'Boolean'],
  [1, 'DateTime'],
  [2, 'Float'],
  [3, 'Integer'],
  [4, 'MultiReference'],
  [5, 'Reference'],
  [6, 'String'],
  [7, 'Activities'],
  [8, 'Addresses'],
  [9, 'Persons'],
  [10, 'SearchComponent'],
])

export const statUnitSearchOptions = [
  { key: 0, text: 'None', value: undefined },
  { key: 1, text: 'StatId', value: 1 },
  { key: 2, text: 'Name', value: 2 },
  { key: 3, text: 'Turnover', value: 3 },
  { key: 4, text: 'Employees', value: 4 },
]

export const predicateComparison = new Map([
  [1, 'SfAnd'],
  [2, 'SfOr'],
])

export const predicateOperations = new Map([
  [1, 'Equal'],
  [2, 'NotEqual'],
  [3, 'GreaterThan'],
  [4, 'LessThan'],
  [5, 'GreaterThanOrEqual'],
  [6, 'LessThanOrEqual'],
  [7, 'Contains'],
  [8, 'NotContains'],
  [9, 'InRange'],
  [10, 'NotInRange'],
  [11, 'InList'],
  [12, 'NotInList'],
])

export const sampleFrameFields = new Map([
  [1, 'UnitType'],
  [2, 'Region'],
  [3, 'MainActivity'],
  [4, 'UnitStatusId'],
  [5, 'Turnover'],
  [6, 'TurnoverYear'],
  [7, 'Employees'],
  [8, 'EmployeesYear'],
  [9, 'FreeEconZone'],
  [10, 'ForeignParticipationId'],
  [13, 'Name'],
  [14, 'StatId'],
  [15, 'TaxRegId'],
  [16, 'ExternalId'],
  [17, 'ShortName'],
  [18, 'TelephoneNo'],
  [19, 'Address'],
  [20, 'EmailAddress'],
  [21, 'ContactPerson'],
  [22, 'LegalForm'],
  [23, 'InstSectorCodeId'],
  [24, 'ActualAddress'],
  [26, 'Size'],
  [27, 'Notes'],
  [28, 'PostalAddress'],
  [30, 'ForeignParticipationCountry'],
])

const forPredicate = oneOf([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 22, 23])

// eslint-disable-next-line max-len
export const sampleFramePredicateFields = new Map([...sampleFrameFields].filter(pair => forPredicate(pair[0])))

export const roles = {
  admin: 'Administrator',
  employee: 'Employee',
  external: 'ExternalUser',
}

export const lookups = new Map([
  [0, 'LocalUnitLookup'],
  [1, 'LegalUnitLookup'],
  [2, 'EnterpriseUnitLookup'],
  [3, 'EnterpriseGroupLookup'],
  [4, 'CountryLookup'],
  [5, 'LegalFormLookup'],
  [6, 'SectorCodeLookup'],
  [7, 'DataSourceClassificationLookup'],
  [8, 'ReorgTypeLookup'],
  [9, 'UnitStatusLookup'],
  [10, 'UnitSizeLookup'],
  [11, 'ForeignParticipationLookup'],
  [12, 'RegionLookup'],
  [13, 'ActivityCategoryLookup'],
])

export const dataSourceUploadTypes = new Map([[1, 'StatUnits']])

export const statUnitChangeReasons = new Map([
  [0, 'Create'],
  [1, 'Edit'],
  [2, 'Correction'],
  [3, 'Delete'],
  [4, 'Undelete'],
])
