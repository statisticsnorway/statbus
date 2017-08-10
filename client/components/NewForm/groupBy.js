import { groupByToArray } from 'helpers/enumerableExtensions'
import Section from './Section'

// TODO: initiate components outside and past as dictionary [[value/group] = component]
export default (fields, errors, onChange, localize) =>
  groupByToArray(fields, v => v.groupName).map(({ key, value }) => Group({ key, value }))
