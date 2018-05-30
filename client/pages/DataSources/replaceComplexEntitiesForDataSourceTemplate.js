const LookupBase = {
  Name: 'Name',
}

const StatId = {
  Name: 'StatId',
}

const CodeLookupBase = {
  ...LookupBase,
  Code: 'Code',
}

const Activity = {
  ActivityType: 'ActivityType',
  ActivityYear: 'ActivityYear',
  Employees: 'Employees',
  Turnover: 'Turnover',
  ActivityCategory: [
    'ActivityCategory',
    {
      ...CodeLookupBase,
    },
  ],
}

const Address = {
  AddressPart1: 'AddressPart1',
  AddressPart2: 'AddressPart2',
  AddressPart3: 'AddressPart3',
  Region: [
    'Region',
    {
      ...CodeLookupBase,
    },
  ],
}

const Person = {
  GivenName: 'GivenName',
  MiddleName: 'MiddleName',
  Surname: 'Surname',
  PersonalId: 'PersonalId',
  BirthDate: 'BirthDate',
  NationalityCode: ['NationalityCode', CodeLookupBase],
  Role: 'Role',
  Sex: 'Sex',
  PhoneNumber: 'PhoneNumber',
}

const ForeignParticipationCountry = {
  ...LookupBase,
  IsoCode: 'IsoCode',
}

function pathsOf(shape, prefix) {
  return Object.values(shape).reduce(
    (acc, value) =>
      typeof value === 'string'
        ? [...acc, [prefix, value]]
        : [...acc, ...pathsOf(value[1], value[0]).map(path => [prefix, ...path])],
    [],
  )
}

function pathToMetaEntry(path) {
  const joined = path.join('.')
  return {
    name: joined,
    localizeKey: joined,
  }
}

function transform(shape, prefix) {
  return pathsOf(shape, prefix).map(pathToMetaEntry)
}

function addFlattened(arr) {
  return arr.reduce((acc, cur) => {
    switch (cur.name) {
      case 'Activities':
        return [...acc, ...transform(Activity, 'Activities')]
      case 'Address':
        return [...acc, ...transform(Address, 'Address')]
      case 'ActualAddress':
        return [...acc, ...transform(Address, 'ActualAddress')]
      case 'ForeignParticipationCountriesUnits':
        return [
          ...acc,
          ...transform(ForeignParticipationCountry, 'ForeignParticipationCountriesUnits'),
        ]
      case 'InstSectorCodeId':
        return [...acc, ...transform(CodeLookupBase, 'InstSectorCodeId')]
      case 'LegalFormId':
        return [...acc, ...transform(CodeLookupBase, 'LegalForm')]
      case 'Persons':
        return [...acc, ...transform(Person, 'Persons')]
      case 'DataSourceClassificationId':
        return [...acc, ...transform(LookupBase, 'DataSourceClassification')]
      case 'EnterpriseUnitRegId':
        return [...acc, ...transform(StatId, 'EnterpriseUnitRegId')]
      case 'LegalUnitId':
        return [...acc, ...transform(StatId, 'LegalUnitId')]
      case 'EntGroupId':
        return [...acc, ...transform(StatId, 'EntGroupId')]
      case 'PersonStatUnits':
      case 'PersonEnterpriseGroups':
      case 'UnitType':
      case 'RegId':
      case 'LocalUnits':
      case 'LegalUnits':
        return acc
      default:
        return [...acc, cur]
    }
  }, [])
}

function transformObject(obj) {
  return {
    localUnit: addFlattened(obj.localUnit),
    legalUnit: addFlattened(obj.legalUnit),
    enterpriseUnit: addFlattened(obj.enterpriseUnit),
  }
}

export default transformObject
