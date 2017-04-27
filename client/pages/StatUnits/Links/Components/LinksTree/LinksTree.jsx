import React from 'react'
import Tree from 'antd/lib/tree'
import { Icon, Loader } from 'semantic-ui-react'
import R from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'

import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'
import LinksGrid from '../LinksGrid'

const TreeNode = Tree.TreeNode

const { func, string, number } = React.PropTypes

const UnitNode = ({ localize, code, name, type }) => (
  <span>
    <Icon name={statUnitIcons(type)} title={localize(statUnitTypes.get(type))} />
    {code && <strong>{code}:</strong>} {name}
  </span>
)

UnitNode.propTypes = {
  localize: func.isRequired,
  code: string,
  name: string.isRequired,
  type: number.isRequired,
}

UnitNode.defaultProps = {
  code: '',
}

const UnitNodeWrapper = shouldUpdate((props, nextProps) => !R.equals(props, nextProps))(UnitNode)

const patchTree = (tree, node, children) => {
  const dfs = nodes => nodes.map((n) => {
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
  const dfs = nodes => nodes.forEach((item) => {
    if (item.children !== null) {
      expandedKeys.add(`${item.id}-${item.type}`)
      dfs(item.children)
    }
  })
  dfs(tree)
  return [...expandedKeys]
}

class LinksTree extends React.Component {
  static propTypes = {
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
    this.fetchUnitsTree()
  }

  componentWillReceiveProps(nextProps) {
    if (nextProps.getUnitsTree !== this.props.getUnitsTree) {
      this.fetchUnitsTree()
    }
  }

  shouldComponentUpdate(nextProps, nextState) {
    return !R.equals(this.props, nextProps) || !R.equals(this.state, nextState)
  }

  onLoadData = (node) => {
    const data = node.props.node
    if (data.children !== null) {
      return new Promise((resolve) => { resolve() })
    }
    return this.props.getNestedLinks({ id: data.id, type: data.type })
      .then((resp) => {
        const isLeaf = resp.length === 0
        this.setState(s => ({
          tree: patchTree(s.tree, data, resp),
          expandedKeys: isLeaf ? s.expandedKeys.filter(v => v !== `${data.id}-${data.type}`) : s.expandedKeys,
        }))
      })
      .catch(() => {
        this.setState(s => ({
          expandedKeys: s.expandedKeys.filter(v => v !== `${data.id}-${data.type}`)
        }))
      })
  }

  onSelect = (keys, { selected, node }) => {
    this.setState({
      selectedKeys: keys,
      links: [],
    }, () => {
      const data = node.props.node
      if (selected) {
        this.props.getUnitLinks({ id: data.id, type: data.type })
          .then((response) => {
            this.setState({ links: response })
          })
          .catch(() => {
            this.setState({ selectedKeys: [] })
          })
      }
    })
  }

  onExpand = (expandedKeys) => {
    this.setState({ expandedKeys })
  }

  fetchUnitsTree = () => {
    const setResultState = (resp) => {
      return this.setState({
        isLoading: false,
        tree: resp,
        expandedKeys: getExpandedKeys(resp),
        selectedKeys: [],
        links: [],
      })
    }
    this.setState({
      isLoading: true,
    }, () => {
      this.props.getUnitsTree()
        .then(resp => setResultState(resp))
        .catch(() => setResultState([]))
    })
  }

  filterTreeNode = (node) => {
    const data = node.props.node
    return data.highlight
  }
  render() {
    const { localize } = this.props
    const { tree, links, selectedKeys, expandedKeys, isLoading } = this.state
    const loop = nodes => nodes.map(item => (
      item.children !== null && item.children.length === 0
        ? <TreeNode title={<UnitNodeWrapper localize={localize} {...item} />} key={`${item.id}-${item.type}`} node={item} isLeaf />
        : (
          <TreeNode title={<UnitNodeWrapper localize={localize} {...item} />} key={`${item.id}-${item.type}`} node={item}>
            {item.children !== null && loop(item.children)}
          </TreeNode>
        )
    ))
    return (
      isLoading
        ? <Loader active inline="centered" />
        : (
          <div>
            {tree.length !== 0 &&
              <Tree
                autoExpandParent={false}
                selectedKeys={selectedKeys}
                expandedKeys={expandedKeys}
                onSelect={this.onSelect}
                onExpand={this.onExpand}
                filterTreeNode={this.filterTreeNode}
                loadData={this.onLoadData}
              >
                {loop(tree)}
              </Tree>
            }
            <LinksGrid localize={localize} data={links} readOnly />
          </div>
        )
    )
  }
}

export default LinksTree
