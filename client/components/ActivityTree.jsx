import React from 'react'
import { func, string, arrayOf, shape } from 'prop-types'
import Tree from 'antd/lib/tree'

import { wrapper } from 'helpers/locale'

const TreeNode = Tree.TreeNode

class ActivityTree extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    callBack: func.isRequired,
    name: string.isRequired,
    label: string.isRequired,
    dataTree: arrayOf(shape({})).isRequired,
    checked: arrayOf(string),
  }

  static defaultProps = {
    checked: [],
  }

  getTreeNodes = reg => this.props.dataTree.filter(x => x.code.match(reg))

  buildTree(parrents, childrens) {
    const tree = parrents.map((p) => {
      const nodes = childrens.filter(f =>
      f.code.substr(0, 1).match(p.code)).map(c =>
      (<TreeNode title={c.name} key={`${c.id}`} />))
      return (<TreeNode title={p.name} key={`${p.id}`} >
        {nodes.length ? nodes : null}
      </TreeNode>)
    })
    return tree
  }

  render() {
    const { localize, name, label, checked, callBack } = this.props

    const parents = this.getTreeNodes(/^[a-z]$/i)
    const childrens = this.getTreeNodes(/^[a-z]{2}$/i)
    const tree = this.buildTree(parents, childrens)

    return (
      <div>
        <label htmlFor={name}>{localize(label)}</label>
        <Tree
          checkable
          checkedKeys={checked}
          onCheck={callBack}
        ><TreeNode title={localize('AllActivities')} key={'all'}>
          {tree}
        </TreeNode>
        </Tree>
      </div>)
  }
}

export default wrapper(ActivityTree)
