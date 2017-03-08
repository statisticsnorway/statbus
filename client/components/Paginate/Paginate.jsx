import React from 'react'
import { Menu } from 'semantic-ui-react'
import { Link } from 'react-router'
import R from 'ramda'

import styles from './styles'

const { func, node, number, shape, string } = React.PropTypes

class Paginate extends React.Component {

  static propTypes = {
    query: shape({
      page: number,
      pageSize: number,
    }),
    totalPages: number,
    queryString: string,
    onChange: func.isRequired,
    children: node.isRequired,
  }

  static defaultProps = {
    query: {
      page: 1,
      pageSize: 15,
    },
    totalPages: 1,
    queryString: '',
  }

  handleChange = (name, value) => () => {
    this.props.onChange({ name, value })
  }

  renderPageSizeLink = (value) => {
    const { query: { pageSize }, queryString } = this.props

    const pathname = queryString.includes(`pageSize=${pageSize}`)
      ? R.replace(`pageSize=${pageSize}`, `pageSize=${value}`, queryString)
      : `${queryString}&pageSize=${value}`

    const isCurrent = value === pageSize
    const link = isCurrent
      ? <b>{value}</b>
      : <Link to={pathname}>{value}</Link>

    return (
      <Menu.Item
        key={value}
        onClick={this.handleChange('pageSize', value)}
        content={value}
        disabled={isCurrent}
        as={() => link}
      />
    )
  }

  renderPageLink = (value) => {
    const { query: { page }, queryString } = this.props

    const pathname = queryString.includes(`page=${page}`)
      ? R.replace(`page=${page}`, `page=${value}`, queryString)
      : `${queryString}&page=${value}`

    const isCurrent = value === page
    const link = isCurrent
      ? <b>{value}</b>
      : <Link to={pathname}>{value}</Link>

    return (
      <Menu.Item
        key={value}
        onClick={this.handleChange('page', value)}
        content={value}
        disabled={isCurrent}
        as={() => link}
      />
    )
  }

  render() {
    const { totalPages, children } = this.props
    const pageSizeLinks = [5, 10, 15, 25, 50].map(this.renderPageSizeLink)
    const pageLinks = R.range(1, totalPages).map(this.renderPageLink)

    return (
      <div className={styles.root}>
        <Menu floated="right" pagination>
          {pageSizeLinks}
        </Menu>
        {children}
        <Menu floated="center" pagination>
          {pageLinks}
        </Menu>
      </div>
    )
  }
}

export default Paginate
