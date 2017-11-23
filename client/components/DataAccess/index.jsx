import React from 'react'
import { func, string, arrayOf, shape, bool } from 'prop-types'
import Tree from 'antd/lib/tree'

import { groupByToArray, mapToArray } from 'helpers/enumerable'
import { statUnitTypes } from 'helpers/enums'
import { toCamelCase } from 'helpers/string'
import styles from './styles.pcss'

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
    label: string.isRequired,
    value: shape({
      legalUnit: validUnit,
      localUnit: validUnit,
      enterpriseUnit: validUnit,
      enterpriseGroup: validUnit,
    }).isRequired,
    name: string.isRequired,
    onChange: func.isRequired,
    localize: func.isRequired,
    readEditable: bool.isRequired,
    writeEditable: bool.isRequired,
  }

  onCheck = permission => (checkedKeys, { node }) => {
    const { value, name, onChange } = this.props
    const keys = new Set(checkedKeys)
    const type = node.props.node.type
    onChange(null, {
      name,
      value: {
        ...value,
        [type]: value[type].map((v) => {
          const allowed = keys.has(v.name)
          return ({
            ...v,
            [permission]: allowed,
            canWrite: permission === 'canRead' && !allowed
              ? allowed
              : permission === 'canWrite' && allowed
                ? allowed && v.canRead
                : permission === 'canWrite'
                  ? allowed
                  : v.canWrite,
          })
        }),
      },
    })
  }

  render() {
    const { value, label, localize, readEditable, writeEditable } = this.props

    const dataAccessItems = (type, items) =>
      items
        .map(x => ({
          key: x.name,
          name: localize(x.localizeKey),
          type,
          children: null,
        }))
        .sort(compareByName)

    const dataAccessGroups = (type, items) =>
      groupByToArray(items, v => v.groupName)
        .map(x => ({
          key: `Group-${type}-${x.key}`,
          type,
          name: localize(x.key || 'Other'),
          children: dataAccessItems(type, x.value),
        }))
        .sort(compareByName)

    const dataAccessByType = (items, localizeKey) => {
      const type = toCamelCase(localizeKey)
      return {
        key: localizeKey,
        type,
        name: localize(localizeKey),
        children: dataAccessGroups(type, items),
      }
    }

    const loop = (nodes, editable) => nodes.map(item => (
      <TreeNode key={`${item.key}`} title={item.name} node={item} disabled={!editable}>
        {item.children !== null && loop(item.children, editable)}
      </TreeNode>
    ))

    const root = unitTypes.map(v => dataAccessByType(value[toCamelCase(v)], v))

    const checkedReadKeys = [].concat(...unitTypes.map(v =>
      this.props.value[toCamelCase(v)].filter(x => x.canRead).map(x => x.name)))
    const checkedWriteKeys = [].concat(...unitTypes.map(v =>
      this.props.value[toCamelCase(v)].filter(x => x.canWrite).map(x => x.name)))

    return (
      <div className="field">
        <label htmlFor={name}>{label}</label>
        <div id={name} className={styles['tree-wrapper']}>
          <div className={styles['tree-column']}>
            <span>{localize('Read')}</span>
            <Tree
              checkable
              checkedKeys={checkedReadKeys}
              onCheck={this.onCheck('canRead')}
            >
              {loop(root, readEditable)}
            </Tree>
          </div>
          <div className={styles['tree-column']}>
            <span>{localize('Write')}</span>
            <Tree
              checkable
              checkedKeys={checkedWriteKeys}
              onCheck={this.onCheck('canWrite')}
            >
              {loop(root, writeEditable)}
            </Tree>
          </div>

        </div>
      </div>
    )
  }
}

export default DataAccess
