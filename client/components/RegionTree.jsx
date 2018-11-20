import React from 'react'
import { string, arrayOf, shape, bool, func } from 'prop-types'
import Tree from 'antd/lib/tree'

import { transform } from './ActivityTree'
import { getNewName } from '../helpers/locale'
import styles from './styles.pcss'

const { TreeNode } = Tree

class RegionTree extends React.Component {
  static propTypes = {
    name: string.isRequired,
    label: string.isRequired,
    dataTree: shape({}).isRequired,
    checked: arrayOf(string),
    isView: bool,
    localize: func,
    callBack: func,
  }

  static defaultProps = {
    checked: [],
    isView: false,
  }

  getAllChilds(data) {
    return data.map(x => (
      <TreeNode title={x.name} key={`${x.id}`}>
        {x.regionNodes && Object.keys(x.regionNodes).length > 0
          ? this.getAllChilds(x.regionNodes.map(transform))
          : null}
      </TreeNode>
    ))
  }

  getPartialChilds(data, quit) {
    const sumOfIds = []

    data.forEach(x =>
      this.props.checked.includes(x.id)
        ? sumOfIds.push(x.id)
        : x.regionNodes != null &&
            x.regionNodes.forEach(y =>
              this.props.checked.includes(y.id)
                ? sumOfIds.push(x.id, y.id)
                : y.regionNodes != null &&
                    y.regionNodes.forEach(v =>
                      this.props.checked.includes(v.id)
                        ? sumOfIds.push(x.id, y.id, v.id)
                        : v.regionNodes != null &&
                            v.regionNodes.forEach(s =>
                              this.props.checked.includes(s.id) &&
                                sumOfIds.push(x.id, y.id, v.id, s.id)))))

    quit++
    return data.map(x =>
      [...new Set(sumOfIds)]
        .sort()
        .slice(0, 3)
        .some(elem => elem === x.id) &&
        quit < 3 && (
          <TreeNode title={x.name} key={`${x.id}`}>
            {x.regionNodes && Object.keys(x.regionNodes).length > 0
              ? this.getPartialChilds(x.regionNodes, quit)
              : null}
          </TreeNode>
      ))
  }

  render() {
    const { localize, name, label, checked, callBack, dataTree, isView } = this.props
    const checkAllRegions = dataTree.regionNodes.map(x => x.id).every(y => checked.includes(y))
    const quit = 0
    return isView ? (
      <Tree defaultExpandedKeys={['1']}>
        <TreeNode
          className={styles.rootNode}
          title={`${!checkAllRegions ? '' : dataTree.name}`}
          key={`${dataTree.id}`}
        >
          {!checkAllRegions && this.getPartialChilds(dataTree.regionNodes, quit)}
        </TreeNode>
      </Tree>
    ) : (
      <div>
        <label htmlFor={name}>{localize(label)}</label>
        <Tree checkedKeys={checked} onCheck={callBack} checkable>
          <TreeNode title={getNewName(dataTree, true)} key={`${dataTree.id}`}>
            {this.getAllChilds(dataTree.regionNodes.map(transform))}
          </TreeNode>
        </Tree>
      </div>
    )
  }
}

export default RegionTree
