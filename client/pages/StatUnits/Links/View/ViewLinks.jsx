import React from 'react'
import Tree from 'antd/lib/tree'
import { Segment, Icon, Header } from 'semantic-ui-react'
import R from 'ramda'

import { wrapper } from 'helpers/locale'
import statUnitIcons from 'helpers/statUnitIcons'
import statUnitTypes from 'helpers/statUnitTypes'
import ViewFilter from './ViewFilter'
import LinksGrid from '../Components/LinksGrid'

const TreeNode = Tree.TreeNode

const { func, string, number, object } = React.PropTypes

const UnitNode = ({ localize, code, name, type }) => (
  <span>
    <Icon name={statUnitIcons(type)} title={localize(statUnitTypes.get(type))} />
    {code !== '' && <strong>{code}:</strong>} {name}
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

class ViewLinks extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    findUnit: func.isRequired,
    filter: object,
    getUnitLinks: func.isRequired,
    getNestedLinks: func.isRequired,
  }

  static defaultProps = {
    filter: undefined,
  }

  state = {
    tree: [],
    selectedKeys: [],
    expandedKeys: [],
    links: [],
    isLoading: undefined,
  }

  componentDidMount() {
    const { filter } = this.props
    if (filter) this.searchUnit(filter)
  }

  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.props, nextProps)
      || !R.equals(this.state, nextState)
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

  searchUnit = (filter) => {
    const { findUnit } = this.props
    const setResultState = resp => this.setState({
      isLoading: false,
      tree: resp,
      expandedKeys: getExpandedKeys(resp),
      selectedKeys: [],
      links: [],
    })
    this.setState({
      isLoading: true,
    }, () => {
      findUnit(filter)
        .then(setResultState)
        .catch(setResultState)
    })
  }

  filterTreeNode = (node) => {
    const data = node.props.node
    return data.highlight
  }
  render() {
    const { localize, filter } = this.props
    const { tree, links, selectedKeys, expandedKeys, isLoading } = this.state
    const loop = nodes => nodes.map(item => (
      item.children !== null && item.children.length === 0
        ? <TreeNode title={<UnitNode localize={localize} {...item} />} key={`${item.id}-${item.type}`} node={item} isLeaf />
        : (
          <TreeNode title={<UnitNode localize={localize} {...item} />} key={`${item.id}-${item.type}`} node={item} isLeaf={item.isLeaf}>
            {item.children !== null && loop(item.children)}
          </TreeNode>
        )
    ))
    return (
      <div>
        <ViewFilter
          isLoading={isLoading}
          value={filter}
          localize={localize}
          onFilter={this.searchUnit}
        />
        <br />
        {isLoading === false &&
          <Segment>
            <Header as="h4" dividing>{localize('SearchResults')}</Header>
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
          </Segment>
        }
      </div>
    )
  }
}

export default wrapper(ViewLinks)
