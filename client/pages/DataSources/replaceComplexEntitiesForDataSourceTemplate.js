// @flow

type MetaEntry = {
  name: string,
  localizeKey: string,
}

type TotalMeta = {
  localUnit: Array<MetaEntry>,
  legalUnit: Array<MetaEntry>,
  enterpriseUnit: Array<MetaEntry>,
}

const Activity = {
  ActivityType: 'ActivityType',
  ActivityCategory: [
    'ActivityCategory',
    {
      Code: 'Code',
      Name: 'Name',
      Section: 'Section',
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
      Name: 'Name',
      Code: 'Code',
      AdministrativeCenter: 'AdministrativeCenter',
    },
  ],
}

const LookupBase = {
  Code: 'Code',
  Name: 'Name',
}

const Person = {
  GivenName: 'GivenName',
  Surname: 'Surname',
  PersonalId: 'PersonalId',
  BirthDate: 'BirthDate',
  NationalityCode: ['NationalityCode', LookupBase],
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

function addFlattened(arr: Array<MetaEntry>) {
  return arr.reduce((acc, cur) => {
    switch (cur.name) {
      case 'Activities':
        return [...acc, ...transform(Activity, 'Activity')]
      case 'Address':
        return [...acc, ...transform(Address, 'Address')]
      case 'ActualAddress':
        return [...acc, ...transform(Address, 'ActualAddress')]
      case 'ForeignParticipationCountryId':
        return [...acc, ...transform(LookupBase, 'ForeignParticipationCountry')]
      case 'InstSectorCodeId':
        return [...acc, ...transform(LookupBase, 'InstSectorCode')]
      case 'LegalFormId':
        return [...acc, ...transform(LookupBase, 'LegalForm')]
      case 'Persons':
        return [...acc, ...transform(Person, 'Person')]
      case 'DataSourceClassificationId':
        return [...acc, ...transform(LookupBase, 'DataSourceClassification')]
      case 'PersonStatUnits':
      case 'PersonEnterpriseGroups':
      case 'UnitType':
        return acc
      default:
        return [...acc, cur]
    }
  }, [])
}

function transformObject(obj: TotalMeta): TotalMeta {
  return {
    localUnit: addFlattened(obj.localUnit),
    legalUnit: addFlattened(obj.legalUnit),
    enterpriseUnit: addFlattened(obj.enterpriseUnit),
  }
}

export default transformObject
