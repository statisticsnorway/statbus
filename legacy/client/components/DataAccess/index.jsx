import React, { useState } from 'react'
import PropTypes from 'prop-types'
import Tree from 'antd/lib/tree'
import { groupByToArray, mapToArray } from '/helpers/enumerable'
import { statUnitTypes } from '/helpers/enums'
import { toCamelCase } from '/helpers/string'
import styles from './styles.scss'

const { TreeNode } = Tree

const unitTypes = mapToArray(statUnitTypes).map(v => v.value)

const validUnit = PropTypes.arrayOf(PropTypes.shape({
  name: PropTypes.string.isRequired,
  allowed: PropTypes.bool.isRequired,
}).isRequired)

const compareByName = (a, b) => {
  if (a.name < b.name) return -1
  if (a.name > b.name) return 1
  return 0
}

function DataAccess(props) {
  const [checkedReadKeys, setCheckedReadKeys] = useState([])
  const [checkedWriteKeys, setCheckedWriteKeys] = useState([])

  const onCheck = permission => (checkedKeys, { node }) => {
    const { value, name, onChange } = props
    const keys = new Set(checkedKeys)
    const { type } = node.props.node
    onChange(null, {
      name,
      value: {
        ...value,
        [type]: value[type].map((v) => {
          const allowed = keys.has(v.name)
          return {
            ...v,
            [permission]: allowed,
            canWrite:
              permission === 'canRead' && !allowed
                ? allowed
                : permission === 'canWrite' && allowed
                  ? allowed && v.canRead
                  : permission === 'canWrite'
                    ? allowed
                    : v.canWrite,
          }
        }),
      },
    })
  }

  const { name, value, label, localize, readEditable, writeEditable } = props

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

  const loop = (nodes, editable, checkedKeys, onCheck) =>
    nodes.map(item => (
      <TreeNode
        key={`${item.key}`}
        title={item.name}
        node={item}
        disabled={!editable}
        checked={checkedKeys.includes(item.key)}
      >
        {item.children !== null && loop(item.children, editable, checkedKeys, onCheck)}
      </TreeNode>
    ))

  const root = unitTypes.map(v => dataAccessByType(value[toCamelCase(v)], v))

  return (
    <div className="field">
      <label htmlFor={name}>{label}</label>
      <div id={name} className={styles['tree-wrapper']}>
        <div className={styles['tree-column']}>
          <span>{localize('Read')}</span>
          <Tree checkable checkedKeys={checkedReadKeys} onCheck={onCheck('canRead')}>
            {loop(root, readEditable, checkedReadKeys, onCheck('canRead'))}
          </Tree>
        </div>
        <div className={styles['tree-column']}>
          <span>{localize('Write')}</span>
          <Tree checkable checkedKeys={checkedWriteKeys} onCheck={onCheck('canWrite')}>
            {loop(root, writeEditable, checkedWriteKeys, onCheck('canWrite'))}
          </Tree>
        </div>
      </div>
    </div>
  )
}

DataAccess.propTypes = {
  label: PropTypes.string.isRequired,
  value: PropTypes.shape({
    legalUnit: validUnit,
    localUnit: validUnit,
    enterpriseUnit: validUnit,
    enterpriseGroup: validUnit,
  }).isRequired,
  name: PropTypes.string.isRequired,
  onChange: PropTypes.func.isRequired,
  localize: PropTypes.func.isRequired,
  readEditable: PropTypes.bool.isRequired,
  writeEditable: PropTypes.bool.isRequired,
}

export default DataAccess
