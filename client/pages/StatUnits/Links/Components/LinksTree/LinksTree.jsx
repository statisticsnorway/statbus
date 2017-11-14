import React from 'react'
import { func, shape } from 'prop-types'
import Tree from 'antd/lib/tree'
import { Loader } from 'semantic-ui-react'
import R from 'ramda'

import UnitNode from './UnitNode'
import LinksGrid from '../LinksGrid'

const patchTree = (tree, node, children) => {
  const dfs = nodes =>
    nodes.map((n) => {
      if (node.id === n.id && node.type === n.type) {
        return { ...n, children: children.map(v => ({ ...v, children: null })) }
      } else if (n.children !== null) {
        return { ...n, children: dfs(n.children) }
      }
      return n
    })
  return dfs(tree)
}

const getExpandedKeys = (tree) => {
  const expandedKeys = new Set()
  const dfs = (nodes) => {
    nodes.forEach((item) => {
      if (item.children === null) return
      expandedKeys.add(`${item.id}-${item.type}`)
      dfs(item.children)
    })
  }
  dfs(tree)
  return [...expandedKeys]
}

const filterTreeNode = node => node.props.node.highlight

class LinksTree extends React.Component {
  static propTypes = {
    filter: shape({}).isRequired,
    localize: func.isRequired,
    getUnitsTree: func.isRequired,
    getUnitLinks: func.isRequired,
    getNestedLinks: func.isRequired,
  }

  state = {
    tree: [],
    selectedKeys: [],
    expandedKeys: [],
    links: [],
    isLoading: undefined,
  }

  componentDidMount() {
    this.fetchUnitsTree(this.props.filter)
  }

  componentWillReceiveProps(nextProps) {
    if (!R.equals(nextProps.filter, this.props.filter)) {
      this.fetchUnitsTree(nextProps.filter)
    }
  }

  shouldComponentUpdate(nextProps, nextState) {
    return !R.equals(this.props, nextProps) || !R.equals(this.state, nextState)
  }

  onLoadData = ({ props: { node } }) =>
    node.children !== null
      ? new Promise((resolve) => {
        resolve()
      })
      : this.props
        .getNestedLinks({ id: node.id, type: node.type })
        .then((resp) => {
          this.setState(s => ({
            tree: patchTree(s.tree, node, resp),
            expandedKeys:
                resp.length === 0
                  ? s.expandedKeys.filter(v => v !== `${node.id}-${node.type}`)
                  : s.expandedKeys,
          }))
        })
        .catch(() => {
          this.setState(s => ({
            expandedKeys: s.expandedKeys.filter(v => v !== `${node.id}-${node.type}`),
          }))
        })

  onSelect = (keys, { selected, node: { props: { node: { id, type } } } }) => {
    this.setState(
      {
        selectedKeys: keys,
        links: [],
      },
      () => {
        if (selected) {
          this.props
            .getUnitLinks({ id, type })
            .then((response) => {
              this.setState({ links: response })
            })
            .catch(() => {
              this.setState({ selectedKeys: [] })
            })
        }
      },
    )
  }

  onExpand = (expandedKeys) => {
    this.setState({ expandedKeys })
  }

  fetchUnitsTree(filter) {
    const setResultState = (resp) => {
      this.setState({
        isLoading: false,
        tree: resp,
        expandedKeys: getExpandedKeys(resp),
        selectedKeys: [],
        links: [],
      })
    }

    this.setState(
      {
        isLoading: true,
      },
      () => {
        this.props
          .getUnitsTree(filter)
          .then(setResultState)
          .catch(() => setResultState([]))
      },
    )
  }

  renderChildren(nodes) {
    return nodes.map((node) => {
      const props = {
        key: `${node.id}-${node.type}`,
        title: <UnitNode localize={this.props.localize} {...node} />,
        node,
      }
      if (node.children !== null) {
        if (node.children.length === 0) props.isLeaf = true
        else props.children = this.renderChildren(node.children)
      }
      return <Tree.TreeNode {...props} />
    })
  }

  render() {
    const { tree, links, selectedKeys, expandedKeys, isLoading } = this.state
    return isLoading ? (
      <Loader active inline="centered" />
    ) : (
      <div>
        {tree.length !== 0 && (
          <Tree
            autoExpandParent={false}
            selectedKeys={selectedKeys}
            expandedKeys={expandedKeys}
            onSelect={this.onSelect}
            onExpand={this.onExpand}
            filterTreeNode={filterTreeNode}
            loadData={this.onLoadData}
          >
            {this.renderChildren(tree)}
          </Tree>
        )}
        <LinksGrid localize={this.props.localize} data={links} readOnly />
      </div>
    )
  }
}

export default LinksTree
