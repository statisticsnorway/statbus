import React from 'react'
import { func, string, arrayOf, shape, bool } from 'prop-types'
import Tree from 'antd/lib/tree'

import { groupByToArray, mapToArray } from 'helpers/enumerableExtensions'
import { wrapper } from 'helpers/locale'
import { statUnitTypes } from 'helpers/enums'
import camelize from 'client/helpers/stringToCamelCase'

const TreeNode = Tree.TreeNode

const unitTypes = mapToArray(statUnitTypes).map(v => v.value)

const validUnit = arrayOf(shape({
  name: string.isRequired,
  allowed: bool.isRequired,
}).isRequired).isRequired

const compareByName = (a, b) => {
  if (a.name < b.name) return -1
  if (a.name > b.name) return 1
  return 0
}

class DataAccess extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    label: string.isRequired,
    value: shape({
      legalUnit: validUnit,
      localUnit: validUnit,
      enterpriseUnit: validUnit,
      enterpriseGroup: validUnit,
    }).isRequired,
    name: string.isRequired,
    onChange: func.isRequired,
  }

  onCheck = (checkedKeys, { node }) => {
    const { value, name, onChange } = this.props
    const keys = new Set(checkedKeys)
    const type = node.props.node.type
    onChange(null, {
      name,
      value: {
        ...value,
        [type]: value[type].map(v => ({
          ...v,
          allowed: keys.has(v.name),
        })),
      },
    })
  }

  render() {
    const { value, label, localize } = this.props

    const dataAccessItems = (type, items) => items.map(v => ({
      key: v.name,
      name: localize(v.localizeKey),
      type,
      children: null,
    })).sort(compareByName)

    const dataAccessGroups = (type, items) => groupByToArray(items, v => v.groupName).map(v => ({
      key: `Group-${type}-${v.key}`,
      type,
      name: localize(v.key || 'Other'),
      children: dataAccessItems(type, v.value),
    })).sort(compareByName)

    const dataAccessByType = (items, localizeKey) => {
      const type = camelize(localizeKey)
      return {
        key: localizeKey,
        type,
        name: localize(localizeKey),
        children: dataAccessGroups(type, items),
      }
    }

    const loop = nodes => nodes.map(item => (
      <TreeNode key={`${item.key}`} title={item.name} node={item}>
        {item.children !== null && loop(item.children)}
      </TreeNode>
    ))

    const root = unitTypes.map(v => dataAccessByType(value[camelize(v)], v))

    const checkedKeys = Array.prototype.concat
      .apply([], unitTypes.map(v =>
        this.props.value[camelize(v)].filter(x => x.allowed).map(x => x.name)
      ))

    return (
      <div className="field">
        <label htmlFor={name}>{label}</label>
        <Tree
          id={name}
          checkable
          checkedKeys={checkedKeys}
          onCheck={this.onCheck}
        >
          {loop(root)}
        </Tree>
      </div>
    )
  }
}

export default wrapper(DataAccess)
