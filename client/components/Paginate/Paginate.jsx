import React from 'react'
import { Menu } from 'semantic-ui-react'
import { Link } from 'react-router'
import R from 'ramda'

import { wrapper } from 'helpers/locale'
import styles from './styles'

const { node, number, func, oneOfType, shape, string } = React.PropTypes

class Paginate extends React.Component {

  static propTypes = {
    routing: shape({
      pathname: string,
      page: oneOfType([number, string]),
      pageSize: oneOfType([number, string]),
      queryString: string,
    }).isRequired,
    totalCount: oneOfType([number, string]),
    children: node.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    totalCount: 0,
  }

  getPage = () => Number(this.props.routing.page) || 1
  getPageSize = () => Number(this.props.routing.pageSize)
  getTotalCount = () => Number(this.props.totalCount)
  getTotalPages = () => Math.ceil(this.getTotalCount() / this.getPageSize())

  getDisplayTotalString() {
    const { localize } = this.props
    const to = this.getPage() * this.getPageSize()
    // eslint-disable-next-line no-mixed-operators
    const from = to - this.pageSize() + 1
    const rangeDescription = this.getTotalPages() === 1
      ? localize('AllOf')
      : `${from} - ${to} ${localize('OfCount')}`
    return `${localize('Displaying')} ${rangeDescription} ${this.getTotalCount()}`
  }

  renderPageSizeLink = (value) => {
    const { pathname, queryString } = this.props.routing

    const nextQueryString = queryString.includes(`pageSize=${this.getPageSize()}`)
      ? R.replace(`pageSize=${this.getPageSize()}`, `pageSize=${value}`, queryString)
      : queryString
        ? `${queryString}&pageSize=${value}`
        : `?pageSize=${value}`

    const isCurrent = value === this.getPageSize()
    const link = isCurrent
      ? <b>{value}</b>
      : <Link to={`${pathname}${nextQueryString}`}>{value}</Link>

    return (
      <Menu.Item
        key={value}
        content={value}
        disabled={isCurrent}
        as={() => link}
      />
    )
  }

  renderPageLink = (value) => {
    const { pathname, queryString } = this.props.routing

    const nextQueryString = queryString.includes(`page=${this.getPage()}`)
      ? R.replace(`page=${this.getPage()}`, `page=${value}`, queryString)
      : queryString
        ? `${queryString}&page=${value}`
        : `?page=${value}`

    const isCurrent = value === this.getPage()
    const link = isCurrent
      ? <b>{value}</b>
      : <Link to={`${pathname}${nextQueryString}`}>{value}</Link>

    return (
      <Menu.Item
        key={value}
        content={value}
        disabled={isCurrent}
        as={() => link}
      />
    )
  }

  renderFooter() {
    const totalPages = this.getTotalPages()
    const page = this.getPage()
    const leftside = page < 5
    const rightside = page > totalPages - 4
    const pageLinks = totalPages > 8
      ? [
        ...R.range(1, leftside ? page + 2 : 2).map(this.renderPageLink),
        ...(leftside ? [] : [<span key="left_dots">{'...'}</span>]),
        ...(leftside && rightside ? [] : R.range(page - 1, page + 2)).map(this.renderPageLink),
        ...(rightside ? [] : [<span key="right_dots">{'...'}</span>]),
        ...R.range((rightside ? page : totalPages) - 1, totalPages + 1).map(this.renderPageLink),
      ]
      : R.range(1, totalPages + 1).map(this.renderPageLink)
    return (
      <div className={styles.footer}>
        {this.props.localize('PageNum')}: {pageLinks}
      </div>
    )
  }

  render() {
    const pageSizeLinks = [5, 10, 15, 25, 50].map(this.renderPageSizeLink)
    return (
      <div className={styles.root}>
        <div className={styles.header}>
          <span className={styles.totalCount}>
            {this.getDisplayTotalString()}
          </span>
          <div className={styles.pageSizeLinks}>
            {this.props.localize('PageSize')}: {pageSizeLinks}
          </div>
        </div>
        {this.props.children}
        {this.renderFooter()}
      </div>
    )
  }
}

export default wrapper(Paginate)
